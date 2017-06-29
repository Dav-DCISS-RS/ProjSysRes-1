#!/usr/bin/perl

use Config::IniFiles; # Pour pouvoir lire les fichiers de config en dehors de Perl
use ldap_lib; # Pour interagir avec l'annuaire
use List::Compare; # Pour comparer des listes
use POSIX qw/strftime ceil/; # Pour generer un timestamp (strftime) ou l'entier immediatement superieur (ceil)
use IO::File; # Pour manipuler des fichiers
use DBI(); # Database Interface pour interagir avec la BD
use Digest::MD5 qw(md5); # Pour utiliser l'algo de hachage des mots de passe MD5
use MIME::Base64 qw(encode_base64); # Pour encoder des chaines de caracteres en base 64
use Getopt::Long; # Pour gerer les options de @ARGV avec la fonction GetOptions()
use Data::Dumper:; # Filtre pour utiliser la fonction Dump() pour le debogage
use strict;
use warnings;


#-----------------------------------------------------------------------
# INITIALISATION ET DECLARATION DE VARIABLES
#-----------------------------------------------------------------------

GetOptions(\%options,
           "verbose", # Passe en mode bavard
           "debug", # Passe en mode debogage
           "commit", # Met a jour
           "help|?"); # Affiche l'aide# Declaration

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

# Declaration
my $CFGFILE = "sync.cfg";
# Inifiles : met le fichier de configuration dans une variable pour qu'il puisse être lu en dehors des scripts Perl
my $cfg = Config::IniFiles->new( -file => $CFGFILE );

# parametres generaux
$config{'scope'}  = $cfg->val('global','scope');

my %params;
# Appel de la fonction init_config (definie plus bas) avec comme parametre %params (declare au dessus et non initialise) et $cfg (fichier de config))
&init_config(\%params, $cfg);

# Appel des methodes connect_dbi (ci-dessous) et connect_ldap (de ldap_lib.pm)
# Etablit la connection a la base de donnees et a l'annuaire LDAP avec les parametres du fichier config mis en variable precedemment
my $dbh  = connect_dbi($params{'db'});
my $ldap = connect_ldap($params{'ldap'});

# Met dans une table de hachage les valeurs qui nous serviront pour utiliser LDAP
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
$ldap = connect_ldap(%ldap_config);

# Declaration des variables globales sans initialisation
my ($query,$sth,$res,$row,$user,$groupname,%expire);
my ($lc);
my (@adds,@mods,@dels);
my (@SIusers,@LDAPusers);
my (@SIgroups,@LDAPgroups);
my ($dn,%attrib);

# Date : on peut utiliser la var today pour voir l'expiration de l'utilisateur
# my $today = strftime "%d"."/"."%m"."/"."%Y", localtime;
my $today = strftime "%Y%m%d%H%M%S", localtime;

#-----------------------------------------------------------------------
# FIN INITIALISATION ET DECLARATION DE VARIABLES
#-----------------------------------------------------------------------



#-----------------------------------------------------------------------
# RECUPERATION DES INFORMATIONS 
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
# RECUPERATION DES INFORMATIONS
#-----------------------------------------------------------------------



#-----------------------------------------------------------------------
# AJOUT
#-----------------------------------------------------------------------


#-----------------------------------------------------------------------
# FIN AJOUT
#-----------------------------------------------------------------------




#-----------------------------------------------------------------------
# SUPRESSION
#-----------------------------------------------------------------------


#-----------------------------------------------------------------------
# FIN SUPRESSION
#-----------------------------------------------------------------------








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

#-----------------------------------------------------------------------
# FIN FONCTIONS
#-----------------------------------------------------------------------
