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
print "\n" . "-" x 80 . "\n";
print "\nSynchronisation BD <-> LDAP\n";
print "Date du jour : $today\n";
print "\n" . "-" x 80 . "\n\n";

#----------------------------------------------------------------------------------------------
#                    Recuperation de la liste des utilisateurs LDAP & SI
#----------------------------------------------------------------------------------------------

# Requête 1
$query = $cfg->val('queries', 'get_users');
if ($options{'debug'}) {
	print "1ere requête SQL : \n";
	print $query."\n";
}		
$sth = $dbh->prepare($query);
$res = $sth->execute;
while ($row = $sth->fetchrow_hashref) {
	my $identifiant = $row->{identifiant};
	push(@SIusers,$row->{identifiant});
}

# Affichage du nombre d'utilisateurs dans SI, et de leur id en mode debug
print("\nUtilisateur(s) dans la BD SI : " . scalar(@SIusers) . "\n");
if ($options{'debug'}) {
	warn Dumper(@SIusers);
}

# Affichage du nombre d'utilisateurs dans LDAP, et de leur id en mode debug
@LDAPusers = sort(get_users_list($ldap,$cfg->val('ldap','usersdn')));
print("\nUtilisateur(s) dans LDAP avant ajout : " . scalar(@LDAPusers) . "\n");
if ($options{'debug'}) {
	warn Dumper(@LDAPusers);
}

#---------------------------------------------------------------------------------------------

# Synchronisation des 2 listes d'utilisateurs
# Affichage des différences en mode debug
print"\nSynchronisation...\n";

$lc = List::Compare->new(\@SIusers, \@LDAPusers);
if ($options{'debug'}) {
	warn Dumper($lc);
}	
print "\n";

#-------------------------------------------------------------------------------------------
#                  Ajout Utilisateur
#-------------------------------------------------------------------------------------------

# On vérifie si l'entrée dans la BD existe dans l'annuaire LDAP
# Si elle est absente, on ajoute l'utilisateur

# Pour chaque identifiant utilisateur à ajouter
@adds = sort($lc->get_unique);
# warn Dumper(@adds); # Dumper (@adds) générant une erreur 
foreach $identifiant (@adds) {
    # Si celui-ci n'est pas déjà présent dans l'annuaire
    if(!ldap_lib::exist_entry($ldap,$cfg->val('ldap','usersdn'),"(uid=$identifiant)")) {
        # On liste les utilisateurs
	$query = $cfg->val('queries', 'get_users');
	# En mode debug seulement, on affiche la requête
	if ($options{'debug'}) {
		print "Requête SQL : \n";
		print $query."\n";
	}		
	# On l'exécute sur la BD
	$sth = $dbh->prepare($query);
	$res = $sth->execute;
	if ($options{'debug'}) {
	print $res;
	}	
	# Pour chaque ligne utilisateur récupérée
	while ($row = $sth->fetchrow_hashref) {
            # On prend son identifiant
            my $identifiant = $row->{identifiant};
            print "Identifiant : \n";
            warn Dumper($identifiant);
            # Et on l'ajoute à la liste utilisateurs de la BD
            push(@SIusers,$row->{identifiant});
            # On affiche les différents champs utilisateurs
            printf "%s %s %s %s %s\n", $row->{identifiant}, $row->{nom},$row->{prenom}, $row->{courriel}, $row->{id_utilisateur};
            # On met les champs dans la table %attrib déclarée précédemment
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
            if ($options{'debug'}) {
            	warn Dumper(%attrib);
            }
            # En mode commit, on met à jour l'annuaire en ajoutant l'utilisateur
            if ($options{'commit'}) {
            	ldap_lib::add_user($ldap,$row->{identifiant},$cfg->val('ldap','usersdn'),%attrib);
            }
	}	
    }
}

@LDAPusers = sort(get_users_list($ldap,$cfg->val('ldap','usersdn')));
print("Utilisateurs dans LDAP après ajout : " . scalar(@LDAPusers) . "\n");
if ($options{'debug'}) {
	warn Dumper(@LDAPusers);
	print "\n";
}

#---------------------------------------------------------------------------------------------
#                       Suppression et modification d'un Utilisateur
#---------------------------------------------------------------------------------------------

$lc = List::Compare->new(\@SIusers, \@LDAPusers);
my $modif_type="";
@dels = sort($lc->get_Ronly);
@mods = sort(!($lc->get_Ronly)); #algo: pour tous ceux qui ne sont pas que ds LDAP -> modif

#if (scalar(@dels) > 0) {
#  foreach my $u (@dels) {
#    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
#    if ($options{'commit'}) {
#    	ldap_lib::del_entry($ldap,$dn);
#    	printf("Suppression %s\n",$dn);
#    }
#  }
#}

# Modification des parametres utilisateurs dans l'annuaire LDAP

if (scalar(@mods) > 0) {
	print scalar(@mods) . " utilisateur(s) à modifier\n";
	foreach my $u (@mods) {
  	  # Parametres
  	  $modif_type="";
  	  $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
   	  # Initialisation des éléments LDAP
   	  my %info = read_entry($ldap,$cfg->val('ldap','usersdn'),"(uid=".$u.")",('mail','shadowExpire','userPassword'));
   	  # Initialisation des éléments SI (requête)
   	  $query = $cfg->val('queries', 'get_users');
   	  $sth = $dbh->prepare($query);
   	  $res = $sth->execute;
   	  while ($row = $sth->fetchrow_hashref) {
   	  	push(@SIusers,$row->{identifiant});
   	  	printf "%s %s %s %s %s\n", $row->{identifiant}, $row->{nom},$row->{prenom}, $row->{courriel}, $row->{id_utilisateur};
   	  		
   	  	if($row->{courriel} ne $info{'mail'}) {  # ne operateur entre string "not equal"
       			# Traces pour voir si les champs s'initialisent correctement
       			if ($options{'debug'}) {
       			print "\nMail SI avant synchro : " . $row->{courriel};
	        	print "\nMail LDAP avant synchro : " . $info{'mail'};
	        	}
	        	# Mise à jour du champ (mode commit)
	        	if ($options{'commit'}) {
       			modify_attr($ldap,$dn,'mail'=>$row->{courriel});
	        	$modif_type="mail";
	        	}
   	  	}
   	  	if(date2shadow($row->{date_expiration}) != $info{'shadowExpire'}) {
   	  		if ($options{'debug'}) {
   	  		print "\nDate exp SI avant synchro : " . $row->{date_expiration};
	        	print "\nDate exp LDAP avant synchro : " . $info{'shadowExpire'};
	        	}
	        	if ($options{'debug'}) {
       			modify_attr($ldap,$dn,'shadowExpire'=>date2shadow($row->{date_expiration}));
	        	$modif_type="expire";
	        	}
   	    	}
		if(gen_password($row->{mot_passe}) ne $info{'userPassword'}) {
			if ($options{'debug'}) {
			print "\nMdP SI avant synchro : " . $row->{mot_passe};
	        	print "\nMdP LDAP avant synchro : " . $info{'userPassword'};
	        	}
	        	if ($options{'debug'}) {
	        	modify_attr($ldap,$dn,'userPassword'=>gen_password($row->{mot_passe}));
         		$modif_type="password";
         		}
           	}
	    	if($modif_type ne "") {
       			printf("Modification de %s [".$modif_type."]\n",$dn . "\n"); #if $options{'verbose'};
            	}
	}
    }
}
    
# pour tous ceux qui ne sont que dans LDAP -> suppression (optimisation de l'algo) 
### else foreach my $v (!@mods) ne semble pas fonctionner, pour l'instant retour à foreach my $v (@dels) ###
foreach my $v (@dels) {
	$dn = sprintf("uid=%s,%s",$v,$cfg->val('ldap','usersdn'));
	if ($options{'commit'}) {
	  ldap_lib::del_entry($ldap,$dn);
	}
	  printf("Suppression de %s \n",$dn . "\n"); #if $options{'verbose'};
	}


#------------------------------------------------------------------------
#                          GROUPES
#------------------------------------------------------------------------
#1/afficher la liste des membres d’un groupe
#2/modifier les membres d’un groupe (ajouter un membre / supprimer un membre)
#3/supprimer un groupe (à condition qu’il ne contienne plus aucun membre et qu’il ne s’agisse pas du
#groupe primaire d’un utilisateur)

# Variables
my (@db_groups_name,@ldap_groups_name);
my (@db_group_users_login,@ldap_group_users_login);

# Liste des groupes dans SI
$sth = $dbh->prepare($query);
$res = $sth->execute;
while ($row = $sth->fetchrow_hashref) {
            my $groupe = $row->{id_groupe};
            push(@SIgroups,$row->{id_groupe});
}

print("\nGroupe(s) dans la BD SI : " . scalar(@SIgroups) . "\n");
if ($options{'debug'}) {
	warn Dumper(@SIgroups);
}

# Liste des groupes dans LDAP
# @LDAPgroups = sort(get_groups_list($ldap,$cfg->val('ldap','groupsdn')));
@LDAPgroups = sort(get_posixgroups_list($ldap,$ldap_config{'ldap','groupsdn'}));
print("\nGroupe(s) dans LDAP avant ajout : " . scalar(@LDAPgroups) . "\n");
if ($options{'debug'}) {
	warn Dumper(@LDAPgroups);
}

# Comparaison des groupes BD et LDAP
$lc = List::Compare->new(\@SIgroups, \@LDAPgroups);

# Groupes à ajouter dans la base LDAP
@adds = sort($lc->get_Lonly);
my $group_infos;
foreach my $g (@adds) {
   add_posixgroup(
        $ldap,
        $cfg->val('ldap','groupsdn'),
        (
            'cn'=>$group_infos->{nom},
            'gidNumber'=>$group_infos->{id_groupe},
            'description'=>$group_infos->{description}
        )
    );

    printf "Adding the group $g in LDAP base.";
}

# Groupes à supprimer de la base LDAP
@dels = sort($lc->get_Ronly);
foreach my $g (@dels) {
    $dn = sprintf("cn=%s,%s",$g,$cfg->val('ldap','groupsdn'));
    ldap_lib::del_entry($ldap,$dn);
    printf "Suppression du groupe $g de LDAP\n";
}

# Ajout d'un membre dans le groupe
my @db_group_users;

# Parcours de tous les groupes
foreach my $data (@SIgroups) {
    @db_group_users_login = ();
    @ldap_group_users_login = ();
    
    # Récupération des utilisateurs du groupe en question
    my($group_id) = @_;
    my $sql = $dbh->prepare('SELECT u.* FROM group_members gm INNER JOIN groups g ON g.group_id=gm.group_id INNER JOIN users u ON gm.user_id = u.user_id WHERE g.group_id = ?');
    $sql->execute($group_id);
    my $db_group_users = $sql->fetchall_arrayref;; # arrayref à remplacer par fetchrow_hashref ?

    # On place dans un tableau les identifiants des utilisateurs inscrits dans le groupe
    foreach my $i (@$db_group_users) {
        push(@db_group_users_login,$i->[1]);
    }

    # On récupère les identifiants des utilisateurs du groupe LDAP
    @ldap_group_users_login=ldap_lib::get_posixgroup_members($ldap,$ldap_config{'groupsdn'},$data->[1]);

    # On compare les utilisateurs des groupes BD et LDAP
    $lc = List::Compare->new(\@db_group_users_login, \@ldap_group_users_login);

    # On ajoute les utilisateurs sur LDAP
    @adds = sort($lc->get_Lonly);
    foreach my $u (@adds) {
        posixgroup_add_user(
            $ldap,
            $ldap_config{'groupsdn'},
            $data->[1], # Nom groupe
            $u
        );
        printf "Ajout de l'utilisateur $u dans le groupe $data->[1] dans la base LDAP.\n";
    }

    # On supprime les utilisateurs de LDAP
    @dels = sort($lc->get_Ronly);
    foreach my $u (@dels) {
        $dn = sprintf("cn=%s,%s",$data->[1],$cfg->val('ldap','groupsdn'));

        ldap_lib::del_attr(
            $ldap,
            $dn,
            ('memberUid'=>$u)
        );

        printf "Suppression de l'utilisateur $u du groupe $data->[1] dans LDAP\n";
    }
}

print "\n\n";

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
