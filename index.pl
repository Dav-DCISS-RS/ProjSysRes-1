#!/perl/bin/perl

# use CGI qw(:all);
# use DBI;
# use verif;
use CGI;
use DBI;
use DBD::mysql;
use warnings;
use strict;
my $url = "/usr/local/var/apache2/cgi-bin/script.pl";
print "Location: $url\n\n";

# Configuration des var de la BDD
my $platform = "mysql";
# TODO changer si avec le nom de la BDD
my $database = "si";
my $host = "localhost";
# TODO changer port si besoin
my $port = "8000";

# Table utilisee
my $tablename = "utilisateur";
# my $tablename2 = "groupe";
# my $tablename3 = "membre";
# my $tablename4 = "membres";

# Info BDD admin
my $user = "root";
my $pw = "root";
my $q = new CGI;

# Nom source donnees
my $dsn = "dbi:mysql:$database:localhost:8000";

# Connection perl DBI
my $connect = DBI->connect($dsn, $user, $pw)
# En cas de probleme :
or die $DBI::errstr;

# Parametres pour le formulaire html
my $id = $q->param('id');
my $pwd = $q->param('pwd');

print $q->header;

# si id = dans si-BDD
#   si user.psw = dans BDD
#   alors connexion ok
# sinon print psw ou id invalide
my %arguments = my $query->Vars;
my $html;
if(%arguments) {
  my $dbh = DBI->connect("DBI:mysql:$database:$host",$user,$pw,{RaiseError => 1});
  my $sth = $dbh->prepare("SELECT COUNT(id) FROM utilisateurs WHERE UPPER(id) = UPPER(?) AND password = ?");
  my $count;
  my $arguments;
  $sth->execute($arguments{identifiant},crypt($arguments{password},$arguments{identifiant}));
  $sth->bind_columns(\$count);
  $sth->fetch;
  if($count == 1) {
    # print $q->redirect(-uri => 'http://localhost/~Ccl/ProjRes/loged-index.html');
    # print "<META HTTP-EQUIV=refresh CONTENT=\"1;URL=loged-index.html\">\n";
  } else {
    $html .= qq ~
    <span style='color:red'>Error: that username and password combination does not match any currently in our database.</span>
    ~;
  }
}
