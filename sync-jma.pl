#!/usr/bin/perl -w
#
# Version 0.2 - 27/03/2017
#
use strict;
use Config::IniFiles;
use ldap_lib;
use List::Compare;
use POSIX qw/strftime ceil/;
use IO::File;
use DBI();
use Digest::MD5 qw(md5);
use MIME::Base64 qw(encode_base64);
use Getopt::Long;
use Data::Dumper::Simple;

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
$config{'scope'}  = $cfg->val('global','scope');
my %params;
&init_config(\%params, $cfg);
my $dbh  = connect_dbi($params{'db'});
my $ldap = connect_ldap($params{'ldap'});

# Declaration variables globales
my ($query,$sth,$res,$row,$user,$groupname,%expire);
my ($lc);
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
# Je suppose que le code ci-dessous effectue la requête ?
$sth = $dbh->prepare($query);
$res = $sth->execute;
while ($row = $sth->fetchrow_hashref) {
   $user = $row->{identifiant};
   # push c'est ajouter à une liste en php c'est sûrement pareil en Perl
   push(@SIusers,$row->{identifiant});
   printf "%s %s %s %s %s\n", $row->{identifiant}, $row->{nom}, $row->{prenom}, $row->{courriel}, $row->{id_utilisateur};
}

# recuperation de la liste des utilisateurs LDAP
print "\n";
print "Utilisateurs LDAP \n";
@LDAPusers = sort(get_users_list($ldap,$cfg->val('ldap','usersdn')));

foreach my $i (@LDAPusers){
	printf $i;
	printf "\n";
}


# Comparaison des deux listes d'utilisateurs (BDD et LDAP)
$lc = List::Compare->new(\@SIusers, \@LDAPusers);
# On stocke les différences (utilisateurs présents dans ldap uniquement) dans une var
@dels = sort($lc->get_Ronly);
# Seulement s'il y a utilisateurs on exécute le code suivant
if (scalar(@dels) > 0) {
  print "Ceci s'affiche s'il y a des utilisateurs à supprimer";
  foreach my $u (@dels) {
    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
    printf("Suppression %s\n",$dn); #if $options{'verbose'};
    # le supprimer dans la base LDAP
    @LDAPusers = del_entry($ldap, $cfg->val('ldap','usersdn','@dels'));

print "Utilisateurs après modif :\n";

foreach my $i (@LDAPusers){
	printf $i;
	printf "\n";
}

   # $ldap->delete("uid=%s");
   # print("Affichage de var dn : $dn");
   # print("Affichage de var s : uid=%s");
   # $ldap->delete("uid=%s",$dn);
   # print("Fin test");
  }
}
# On vérifie la présence d'utilisateurs dans BDD mais pas LDAP (création)
#add user
@adds = sort($lc->get_Lonly);
if (scalar(@adds) > 0) {
  print "Ceci s'affiche s'il y a des utilisateurs à créer";
  foreach my $u (@adds) {
    print "Ajout de : \n";
    print $u;
    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
    printf("Création %s\n", $dn);
    ldap_lib::add_user($ldap,$user->{login},$cfg->val('ldap','usersdn'),
        (
            'cn'=> $user->{firstname}." ".$user->{name},
            'sn'=>$user->{name},
            'givenName'=>$user->{firstname},
            'mail'=>$user->{mail},
            'uidNumber'=>$user->{user_id},
            'gidNumber'=>$user->{group_id},
            'homeDirectory'=>"/home/".$user->{login},
            'loginShell'=>"/bin/bash",
            'userPassword'=>gen_password($user->{password}),
            'shadowExpire'=>date2shadow($user->{expire})

        ));

    printf("Ajout de %s\n",$dn); #if $options{'verbose'};

    }
}
print "\n";
print ("utilisateurs dans ldap apr�s traitement :\n");
foreach my $i (@LDAPusers){
	printf $i;
	printf "\n";
}

$dbh->disconnect;
$ldap->unbind;


#-----------------------------------------------------------------------
# fonctions
#-----------------------------------------------------------------------
sub init_config {
  (my $ref_config, my $cfg) = @_;

  $$ref_config{'ldap'}{'server'}  = $cfg->val('ldap','server');
  $$ref_config{'ldap'}{'version'} = $cfg->val('ldap','version');
  $$ref_config{'ldap'}{'port'}    = $cfg->val('ldap','port');
  $$ref_config{'ldap'}{'binddn'}  = $cfg->val('ldap','binddn');
  $$ref_config{'ldap'}{'passdn'}  = $cfg->val('ldap','passdn');

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

  my $hashPassword = "{MD5}" . encode_base64( md5($clearPassword),'' );
  return($hashPassword);
}

sub date2shadow {

  my $date = shift;

  chomp(my $timestamp = `date --date='$date' +%s`);
  return(ceil($timestamp/86400));
}

# sub suppr_usr {
#  my $suppr = "DROP TABLE `users`";
#  my $newusr = "CREATE TABLE `users` (   `username` varchar(60) NOT NULL default '',   `password` varchar(32) default NULL,   `fullname` varchar(50) NOT NULL default '',   `type` enum('A','D','U','R','H') default NULL,   `quarantine_report` tinyint(1) default '0',   `spamscore` tinyint(4) default '0',   `highspamscore` tinyint(4) default '0',   `noscan` tinyint(1) default '0',   `quarantine_rcpt` varchar(60) default NULL,   PRIMARY KEY  (`username`) ) ENGINE=MyISAM DEFAULT CHARSET=latin1;";
#  $DBH->do($drop);
#  $DBH->do($create);
#}
