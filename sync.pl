#!/perl/bin/perl

# use CGI qw(:all);
# use DBI();
# use verif;
use CGI;
use DBI;
use DBD::mysql;
use warnings;
use strict;
# On ajoute la lib ldap fournie par JMA
use ldap_lib;

my %params;
my $db = connect_dbi($params{'si'});
my $ldap = connect_ldap($params{'ldap'});
# (Ccl commentaire ->) TODO Vérifier les paramètres ldap si le nom
# est différent le script ne s'éxécutera pas donc changer le nom dans
# les params si nécéssaire si c'est bon effacer ce commentaire

# Déclaration des variables globales (code JMA)
my ($query, $sth, $res, $row, $user, $groupname, %expire);
my ($lc);
my (@adds, @mods, @dels);
my (@SIusers, @LDAPusers);
my (@SIgroups, @LDAPgroups);
my ($dn, %attrib);


# TEST (Ccl commentaire) TODO effacer ce code s'il fonctionne
# Permet de vérifier que le lien engtre ldap et bdd est bien
# effectué 

print("Test, ce code affiche les utilisateurs de la bdd");
$query = $cfg->val('queires', 'get_users');
print $query."\n";
$sth = $dbh->prepare($query);
$res = $sth->execute;
while($row = $sth>fetchrow_hashref) {
	$user = $row->{identifiant};
	push(@SIusers, $row->{identifiant});
	printf "%S %s %s %s %s\n", $row->{identifiant}, $row->{nom}, $row->{prnom}, $row->{courriel}, $row->{id_utilisateur};
}
# PSEUDO-CODE
# 
# if connexion db not possible
#  print message erreur : connexion impossible
# endif
# USE : connect_ldap()
#
# TODO : Peut-etre que la connexion est mieux dans un script a part ?
#
# NOTE : soit i le num id
# NOTE : il faut checker chaque entree de chaque ligne du coup suremenet qu'il faudra une 
#        deuxieme boucle, je suis encore dans les schemas de la DB la
# for i // db
#  i.el = entree1
#  for i // ldap
#    i.el =  entree2
#    if entree1 != entree2
#     print entree2 remplacee par entree1
#     entree2 = entree1
#    endif
#  endfor
#  i++
# endfor
