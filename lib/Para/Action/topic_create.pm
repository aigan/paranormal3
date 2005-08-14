#  $Id$  -*-perl-*-
package Para::Action::topic_create;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw uri );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 2 )
    {
	throw('denied', "Du har inte access för att skapa ett ämne");
    }

    my( $title ) = $q->param('title');
    my $t = Para::Topic->create( $title );

    my @aliases = $q->param('_aliaslist');
    push @aliases, $title;

    foreach my $alias ( @aliases )
    {
	$t->title2aliases( $alias );
    }

    $req->s->route->plan_next( uri "/member/db/topic/view/", {tid => $t->id});

    $q->param('tid', $t->id);

    return "Skapade ämnet $title";
}

1;
