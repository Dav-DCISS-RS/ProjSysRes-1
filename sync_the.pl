#!/usr/bin/perl
use Config::IniFiles;
use ldap_lib;
use List::Compare;
use POSIX qw/strftime ceil/;
use IO::File;
use Digest::MD5 qw(md5);
use MIME::Base64 qw(encode_base64);
use Getopt::Long;
use DBI();
use Data::Dumper;
use strict;
use warnings;

GetOptions(\%options,
           "verbose",
	   "debug",
           "commit",
	   "help|?");



if ($options{'help'}) {
  print "Usage: $0 [--verbose --debug --commit|-c --help|?]\n";
  print " ";
  print "Synchronise les utilisateurs et les groupes depuis les donnees du SI\n";
  print "Options\n";
  print "  --verbose|-v                 mode bavard\n";
  print "  --debug|-d                   mode debug\n";
  print "  --commit|-c                  applique les changements\n";
  print "  --help|-h                    affiche ce message d'aide\n";
  exit (1);
}



my $CFGFILE = "sync.cfg";
my $cfg = Config::IniFiles->new( -file => $CFGFILE );


# parametres generaux
$config{'scope'}  = $cfg->val('global','scope');;
my %params;
&init_config(\%params, $cfg);
my $dbh  = connect_dbi($params{'db'});
my $ldap = connect_ldap($params{'ldap'});

my %ldap_config =  (

    'server' => $cfg->val('ldap','server'),
    'version' => $cfg->val('ldap','version'),
    'port' => $cfg->val('ldap','port'),
    'binddn' => $cfg->val('ldap','binddn'),
    'passdn' => $cfg->val('ldap','passdn'),
    'basedn' => $cfg->val('ldap','basedn'),
    'usersdn' => $cfg->val('ldap','usersdn'),
    'groupsdn' => $cfg->val('ldap','groupsdn')


);

$ldap = connect_ldap(\%ldap_config);


# Declaration variables globales
my ($query,$sth,$res,$row,$user,$groupname,%expire);
my ($lc,$identifiant);
my (@adds,@mods,@dels);
my (@SIusers,@LDAPusers);
my (@SIgroups,@LDAPgroups);
my ($dn,%attrib);
my $today = strftime "%d"."/"."%m"."/"."%Y", localtime;


# On peut utiliser la var today pour voir expiration de l'utilisateur
print "Date du jour : $today\n";



# recuperation des utilisateurs de la BD si
# On peut rajouter les queries dans le fichier config
# Ici le get_users affiche les utilisateurs
print "\n";
print "Utilisateurs BD \n";
$query = $cfg->val('queries', 'get_users');
print "Requête SQL : \n";
print $query."\n" ; # if $options{'debug'};

$sth = $dbh->prepare($query);
$res = $sth->execute;

 while ($row = $sth->fetchrow_hashref) {
            my $identifiant = $row->{identifiant};
            push(@SIusers,$row->{identifiant});
}

#----------------------------------------------------------------------------------------------
#                    Recuperation de la liste des utilisateurs LDAP & SI
#----------------------------------------------------------------------------------------------

print "\n";


print("Utilisateur SI\n");
warn Dumper(@SIusers);

print "\n";

print("Utilisateur LDAP\n");
@LDAPusers = sort(get_users_list($ldap,$cfg->val('ldap','usersdn')));
warn Dumper(@LDAPusers);

#---------------------------------------------------------------------------------------------


print"\nSynchronisation\n";

$lc = List::Compare->new(\@SIusers, \@LDAPusers);
warn Dumper($lc);

#-------------------------------------------------------------------------------------------
#                  Ajout Utilisateur
#-------------------------------------------------------------------------------------------

@adds = sort($lc->get_unique);

 foreach $identifiant (@adds) {
    $dn = sprintf("uid=%s,%s",$identifiant,$cfg->val('ldap','usersdn'));
	
    if(!ldap_lib::exist_entry($ldap,$cfg->val('ldap','usersdn'),"(uid=$identifiant)")) {
        $query = $cfg->val('queries', 'get_users');
        print "Requête SQL : \n";
        print $query."\n" ; # if $options{'debug'};
        $sth = $dbh->prepare($query);
        $res = $sth->execute;
        while ($row = $sth->fetchrow_hashref) {
            my $identifiant = $row->{identifiant};
            push(@SIusers,$row->{identifiant});
            printf "%s %s %s %s %s\n", $row->{identifiant}, $row->{nom},$row->{prenom}, $row->{courriel}, $row->{id_utilisateur};
            $attrib{'cn'} = $row->{prenom}." ".$row->{nom};
            $attrib{'sn'} = $row->{nom};
            $attrib{'givenName'} = $row->{prenom};
            $attrib{'mail'} = $row->{courriel};
            $attrib{'uidNumber'} = $row->{id_utilisateur};
            $attrib{'gidNumber'} = $row->{id_groupe};
            $attrib{'homeDirectory'} = "/home/".$row->{identifiant};
            $attrib{'loginShell'} = "/bin/bash";
            $attrib{'userPassword'} = gen_password($row->{mot_passe});
            $attrib{'shadowExpire'} = date2shadow($row->{date_expiration});

            ldap_lib::add_user($ldap,$row->{identifiant},$cfg->val('ldap','usersdn'),%attrib);
	    printf("Ajout de %s\n",$dn);    
	}
}  
		
			  
#print "Apres ajout dans LDAP : ";
#@LDAPusers = sort(get_users_list($ldap,$cfg->val('ldap','usersdn')));
#warn Dumper(@LDAPusers);

#---------------------------------------------------------------------------------------------
#                       Suppression et modification d'un Utilisateur
#---------------------------------------------------------------------------------------------



# Utilisateurs à supprimer de l'annuaire LDAP
#@dels = sort($lc->get_complement);

#if (scalar(@dels) >0) {
#	print " Suppression dans LDAP :\n";

#	}


#warn Dumper(@LDAPusers);



# Modif dans l'annuaire LDAP
my $modif_type="";
@mods = sort(!($lc->get_Ronly)); #algo: pour tous ceux qui ne sont pas que ds LDAP -> modif
if (scalar(@mods) >0) {
	foreach my $u (@mods) {
  	  $modif_type="";
  	  $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
   	  my %info = read_entry(
                  $ldap,
	          $cfg->val('ldap','usersdn'),
        	  "(uid=".$u.")",
	          ('mail','shadowExpire','userPassword')
   		 );
	    if($user->{courriel} ne $info{'mail'}) {  #ne operateur entre string "not equal"
       		 modify_attr($ldap,$dn,'mail'=>$user->{courriel});
	         $modif_type="mail";
   	    }
   	    if(date2shadow($user->{date_expiration}) != $info{'shadowExpire'}) {
       		 modify_attr($ldap,$dn,'shadowExpire'=>date2shadow($user->{date_expiration}));
	         $modif_type="expire";
   	    }
   	    if(gen_password($user->{mot_passe}) ne $info{'userPassword'}) {
	         modify_attr($ldap,$dn,'userPassword'=>gen_password($user->{mot_passe}));
         	 $modif_type="password";
            }
	    if($modif_type ne "") {
       		 printf("Modification de %s [".$modif_type."]\n",$dn); #if $options{'verbose'};
            }
	}
    }
else {  # pour tous ceux qui ne sont que dans LDAP -> suppression (optimisation de l'algo)
	foreach my $v (!@mods) {
    		$dn = sprintf("uid=%s,%s",$v,$cfg->val('ldap','usersdn'));
		ldap_lib::del_entry($ldap,$dn);
		printf("Suppression de %s\n",$dn); #if $options{'verbose'};
		}
	}

print "\n\n";


#------------------------------------------------------------------------
#                          GROUPES
#------------------------------------------------------------------------



#-----------------------------------------------------------------------
# FONCTIONS
#-----------------------------------------------------------------------
sub init_config {
  (my $ref_config, my $cfg) = @_;
  # VALEURS LDAP
  $$ref_config{'ldap'}{'server'}  = $cfg->val('ldap','server');
  $$ref_config{'ldap'}{'version'} = $cfg->val('ldap','version');
  $$ref_config{'ldap'}{'port'}    = $cfg->val('ldap','port');
  $$ref_config{'ldap'}{'binddn'}  = $cfg->val('ldap','binddn');
  $$ref_config{'ldap'}{'passdn'}  = $cfg->val('ldap','passdn');
  # VALEURS DB
  $$ref_config{'db'}{'database'}  = $cfg->val('db','database');
  $$ref_config{'db'}{'server'}    = $cfg->val('db','server');
  $$ref_config{'db'}{'user'}      = $cfg->val('db','user');
  $$ref_config{'db'}{'password'}  = $cfg->val('db','password');
}

sub connect_dbi {
  my %params = %{(shift)};
  my $dsn = "DBI:mysql:database=".$params{'database'}.";host=".$params{'server'};
  my $dbh = DBI->connect(
			$dsn,
                      	$params{'user'},
		      	$params{'password'},
		      	{'RaiseError' => 1}
		      );
  return($dbh);
}

sub gen_password {
  my $clearPassword = shift;
  my $hashPassword = "{MD5}" . encode_base64(md5($clearPassword),'');
  return($hashPassword);
}

sub date2shadow {
  my $date = shift;
  chomp(my $timestamp = `date --date='$date' +%s`);
  return(ceil($timestamp/86400));
}

print "\n\n";
