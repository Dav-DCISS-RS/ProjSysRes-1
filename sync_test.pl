#!/usr/bin/perl

use Config::IniFiles;
use ldap_lib;
use List::Compare;
use POSIX qw/strftime ceil/;
use IO::File;
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


print"\n########Synchronisation########\n";


my $user;
$lc = List::Compare->new(\@SIusers, \@LDAPusers);


# Users à ajouter dans l'annuaire LDAP

@adds = sort($lc->get_Lonly);
if (scalar(@adds) > 0) {
  print "Ceci s'affiche s'il y a des utilisateurs à créer";
  foreach my $u (@adds) {
    print "$u\n";

    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));

    ldap_lib::add_user($ldap,$user->{identifiant},$cfg->val('ldap','usersdn'),
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


# Utilisateurs à supprimer d'annuaire LDAP

@dels = sort($lc->get_Ronly);

foreach my $u (@dels) {

    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));

    ldap_lib::del_entry($ldap,$dn);

    printf("Suppression de %s\n",$dn); #if $options{'verbose'};
}


# Modifications dans l'annuaire LDAP

my $modif_type="";
@mods = sort($lc->get_intersection);
foreach my $u (@mods) {
    $modif_type="";

    $dn = sprintf("uid=%s,%s",$u,$cfg->val('ldap','usersdn'));
    #scalar ?

    my %info = read_entry(
        $ldap,
        $cfg->val('ldap','usersdn'),
        "(uid=".$u.")",
        ('mail','shadowExpire','userPassword')
    );
    #print gen_password($user->{password})."!=".$info{'userPassword'}."\n";
    if($user->{mail} ne $info{'mail'}){
        modify_attr($ldap,$dn,'mail'=>$user->{mail});
        $modif_type="mail";
    }

    if(date2shadow($user->{expire}) != $info{'shadowExpire'}){
        modify_attr($ldap,$dn,'shadowExpire'=>date2shadow($user->{expire}));
        $modif_type="expire";
    }

    if(gen_password($user->{password}) ne $info{'userPassword'}){
        modify_attr($ldap,$dn,'userPassword'=>gen_password($user->{password}));
        $modif_type="password";
    }


    if($modif_type ne ""){
        printf("Modification de %s [".$modif_type."]\n",$dn); #if $options{'verbose'};
    }
}

print "\n\n";


#################
# GROUPES #
#################


my (@db_groups_name,@ldap_groups_name);
my (@db_group_users_login,@ldap_group_users_login);

# recuperation des groupes de la BD
my $db_groups = db_lib::getGroups();

foreach my $data (@$db_groups) {
    push(@db_groups_name,$data->[1]);
}


# Récupération LDAP groups
@ldap_groups_name = sort(get_posixgroups_list($ldap,$ldap_config{'groupsdn'}));

print "#LDAP Groups#\n";
foreach my $elt (@ldap_groups_name) {
    print "-$elt-\n";
}

print "#DB groups#\n";
foreach my $elt (@db_groups_name) {
    print "-$elt-\n";
}

print"\n###Action###\n";


$lc = List::Compare->new(\@db_groups_name, \@ldap_groups_name);


# Groupes à ajouter dans la base LDAP
@adds = sort($lc->get_Lonly);
foreach my $g (@adds) {

   #scalar ?
   add_posixgroup(
        $ldap,
        $cfg->val('ldap','groupsdn'),
        (
            'cn'=>$group_infos->{name},
            'gidNumber'=>$group_infos->{group_id},
            'description'=>$group_infos->{description}
        )
    );

    printf "Adding the group $g in LDAP base.";
}

# Groupes à retirer de la base LDAP
@dels = sort($lc->get_Ronly);
foreach my $g (@dels) {
    $dn = sprintf("cn=%s,%s",$g,$cfg->val('ldap','groupsdn'));
    ldap_lib::del_entry($ldap,$dn);
    printf "Deleting the group $g of LDAP base.\n";
}



# Ajout d'un membre dans groupe

my @db_group_users;

# Parcours de tous les groupes
foreach my $data (@$db_groups) {

    @db_group_users_login = ();
    @ldap_group_users_login = ();

    # Récupération des utilisateurs du groupe en question
    my $db_group_users = db_lib::getGroupUsers($data->[0]);

    # On place dans un tableau les login des utilisateurs inscrits dans ce groupe (DB)
    foreach my $elt (@$db_group_users) {
        push(@db_group_users_login,$elt->[1]);
    }



    # On récupère les login des utilisateurs de ce groupe (LDAP)
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
        printf "Adding user $u in the group $data->[1] in LDAP base.\n";
    }



    # On le supprime de LDAP
    @dels = sort($lc->get_Ronly);
    foreach my $u (@dels) {
        $dn = sprintf("cn=%s,%s",$data->[1],$cfg->val('ldap','groupsdn'));

        ldap_lib::del_attr(
            $ldap,
            $dn,
            ('memberUid'=>$u)
        );

        printf "Deleting user $u of the group $data->[1] in LDAP base.\n";
    }



}




print "\n\n";
