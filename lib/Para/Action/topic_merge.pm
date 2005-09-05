#  $Id$  -*-perl-*-
package Para::Action::topic_merge;

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
	throw('denied', "Du måste bli väktare för att få slå samman ämnen");
    }


    # Merging t2 into t1 <<<---- NB !!!!


    my $tid1 = $q->param('t1') or throw('incomplete', "Param t1 missing");
    my $tid2 = $q->param('t2') or throw('incomplete', "Param t2 missing");

    my $t1 = Para::Topic->get_by_id( $tid1 );
    my $t2 = Para::Topic->get_by_id( $tid2 );

    $t2->merge($t1);

    $q->param('tid', $tid1);
    return "Ämnena sammanslagna";
}

1;
