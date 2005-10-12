#  $Id$  -*-perl-*-
package Para::Action::topic_publish;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 12 )
    {
	throw('denied', "Enbart för väktare");
    }

    my $tid = $q->param('tid')
	or throw('incomplete', "tid param missing");

    my $t = Para::Topic->get_by_id( $tid );

    $t->publish;
    return $req->change->report;
}

1;
