# -*-cperl-*-
package Para::Action::member_vacuum;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    my $mid = $q->param('mid')
	or throw('incomplete', "mid param missing");

    my $m = Para::Member->get( $mid );
    $m->vacuum;

    return "Medlem städad";
}

1;
