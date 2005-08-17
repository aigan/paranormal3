#  $Id$  -*-perl-*-
package Para::Action::entry_move;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw clear_params );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 12 )
    {
	throw('denied', "Du måste bli väktare för att få flytta texter");
    }

    #Move tid to t2_id

    my $tid1 = $q->param('tid') or die "Param tid missing";
    my $tid2 = $q->param('t2_id') or throw('incomplete', "Du har inte markerat vart du vill flytta texten");

    my $t1 = Para::Topic->get_by_id($tid1); # Should be entry
    my $t2 = Para::Topic->get_by_id($tid2);

    # Check things
    unless( $t1->entry )
    {
	throw('validation', "t1 must be entry");
    }

    # Returns the new version
    $t1 = $t1->create_new_version unless $q->param('keep_version');

    $t1->previous and $t1->previous->set_next( undef );
    $t1->set_parent( $t2 );
    $t1->generate_url;

    $t1->mark_publish;
    $t2->mark_publish;

    clear_params('tid', 't2_id');

    $q->param('tid', $tid1);
    return "Text flyttad";
}

1;
