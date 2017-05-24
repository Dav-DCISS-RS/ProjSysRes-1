#!/perl/bin/perl

# use CGI qw(:all);
# use DBI;
# use verif;
use CGI;
use DBI;
use DBD::mysql;
use warnings;
use strict;
# On ajoute la lib ldap fournie par JMA
require "ldap_lib.pm";

# PSEUDO-CODE
# 
# if connexion db not possible
#  print message erreur : connexion impossible
# endif
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
