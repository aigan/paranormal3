#  $Id$  -*-perl-*-
package Para::Action::entry_create;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw trim );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 5 )
    {
	throw('denied', "Du måste bli medborgare för att få skapa nya texter");
    }

    my $text = $q->param('t_text')
	or throw('incomplete', "t_text param missing");

    my $parent = $q->param('tid')
	or throw('incomplete', "tid param missing");


    my $tid = $Para::dbix->get_nextval( "t_seq" );
    my $sth = $Para::dbh->prepare(
	  "insert into t ( t, t_text, t_created, t_updated, t_createdby,
                           t_changedby, t_status, t_active, t_entry,
                           t_entry_parent, t_entry_imported )
           values ( ?, ?, now(), now(), ?, ?, ?, 't', 't', ?, 1)");
    $sth->execute( $tid, $text, $u->id, $u->id, $u->new_status, $parent ) or die;


    $u->score_change('entry_submitted', 1);

    $q->param('tid',$tid);
    return "Ny text skapad";
}

1;
