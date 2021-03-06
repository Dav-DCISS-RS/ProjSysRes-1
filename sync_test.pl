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
my %vals =  (

    'server' => $cfg->val('ldap','server'),
    'version' => $cfg->val('ldap','version'),
    'port' => $cfg->val('ldap','port'),
    'binddn' => $cfg->val('ldap','binddn'),
    'passdn' => $cfg->val('ldap','passdn'),
    'basedn' => $cfg->val('ldap','basedn'),
    'usersdn' => $cfg->val('ldap','usersdn'),
    'groupsdn' => $cfg->val('ldap','groupsdn')


);
my %ldap_config = %vals;
$ldap = connect_ldap(%ldap_config);

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
print"\nSynchronisation\n";
$user="vide";
$lc = List::Compare->new(\@SIusers, \@LDAPusers);

# Utilisateurs à ajouter dans l'annuaire LDAP
@adds = sort($lc->get_Lonly);
if (scalar(@adds) > 0) {
  print "Ceci s'affiche s'il y a des utilisateurs à créer";
  foreach my $u (@adds) {
    print "$u\n";
    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
    ldap_lib::add_user($ldap,$user->{identifiant},$cfg->val('ldap','usersdn'),
        (
            'cn'=> $user->{prenom}." ".$user->{nom},
            'sn'=>$user->{nom},
            'givenName'=>$user->{prenom},
            'mail'=>$user->{courriel},
            'uidNumber'=>$user->{id_utilisateur},
            'gidNumber'=>$user->{id_groupe},
            'homeDirectory'=>"/home/".$user->{identifiant},
            'loginShell'=>"/bin/bash",
            'userPassword'=>gen_password($user->{mot_passe}),
            'shadowExpire'=>date2shadow($user->{date_expiration})

        ));

    printf("Ajout de %s\n",$dn); #if $options{'verbose'};
  }

}


# Utilisateurs à supprimer de l'annuaire LDAP
@dels = sort($lc->get_Ronly);
foreach my $u (@dels) {
    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
    ldap_lib::del_entry($ldap,$dn);
    printf("Suppression de %s\n",$dn); #if $options{'verbose'};
}


# Modif dans l'annuaire LDAP
my $modif_type="";
@mods = sort($lc->get_intersection);
foreach my $u (@mods) {
    $modif_type="";
    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
    my %info = read_entry(
        $ldap,
        $cfg->val('ldap','usersdn'),
        "(uid=".$u.")",
        ('mail','shadowExpire','userPassword')
    );
    if($user->{courriel} ne $info{'mail'}){
        modify_attr($ldap,$dn,'mail'=>$user->{courriel});
        $modif_type="mail";
    }
    if(date2shadow($user->{date_expiration}) != $info{'shadowExpire'}){
        modify_attr($ldap,$dn,'shadowExpire'=>date2shadow($user->{date_expiration}));
        $modif_type="expire";
    }
    if(gen_password($user->{mot_passe}) ne $info{'userPassword'}){
        modify_attr($ldap,$dn,'userPassword'=>gen_password($user->{mot_passe}));
        $modif_type="password";
    }
    if($modif_type ne ""){
        printf("Modification de %s [".$modif_type."]\n",$dn); #if $options{'verbose'};
    }
}

print "\n\n";


#################
# GROUPES
#################
my (@db_groups_name,@ldap_groups_name);
my (@db_group_users_login,@ldap_group_users_login);

# Récupération des groupes de la BD
my $sql = my $db->prepare('SELECT * FROM groups ORDER BY group_id');
$sql->execute();
my $db_groups = $sql->fetchall_arrayref;
foreach my $data (@$db_groups) {
    push(@db_groups_name,$data->[1]);
}


# Récupération groupes LDAP
@ldap_groups_name = sort(get_posixgroups_list($ldap,$ldap_config{'groupsdn'}));
print "Groupes LDAP\n";
foreach my $i (@ldap_groups_name) {
    print "-$i-\n";
}

print "Groupes DB\n";
foreach my $i (@db_groups_name) {
    print "-$i-\n";
}

$lc = List::Compare->new(\@db_groups_name, \@ldap_groups_name);

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



# Ajout d'un membre dans groupe
my @db_group_users;

# Parcours de tous les groupes
foreach my $data (@$db_groups) {
    @db_group_users_login = ();
    @ldap_group_users_login = ();
    # Récupération des utilisateurs du groupe en question
    my($group_id) = @_;
    my $sql = $db->prepare('SELECT u.* FROM group_members gm INNER JOIN groups g ON g.group_id=gm.group_id INNER JOIN users u ON gm.user_id = u.user_id  WHERE g.group_id=? ');
    $sql->execute($group_id);
    my $db_group_users = $sql->fetchall_arrayref;;

    # On place dans un tableau les identifiants des utilisateurs inscrits dans le groupe
    foreach my $i (@$db_group_users) {
        push(@db_group_users_login,$i->[1]);
    }

    # On récupère les identifiants des utilisateurs du groupe LDAP
    @ldap_group_users_login=ldap_lib::get_posixgroup_members($ldap,$ldap_config{'groupsdn'},$data->[1]);

    $lc = List::Compare->new(\@db_group_users_login, \@ldap_group_users_login);

    # On l'ajoute sur LDAP
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

    # On supprime de LDAP
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
