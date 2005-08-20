#  $Id$  -*-perl-*-
package Para::Action::mailbox_change_quota;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 41 )
    {
	throw('denied', "Du har inte access för att ändra quota");
    }

    my $mid = $q->param('mid')
	or throw('incomplete', "mid param missing");

    my $m = Para::Member->get_by_id( $mid );

    my $quota = $q->param('quota')||10000;
    $m->mailbox->quota( $quota );

    my $name = $m->nickname;

    $q->delete('quota');

    return "Quota ändrad till $quota för $name";
}

1;
