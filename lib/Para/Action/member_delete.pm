#  $Id$  -*-perl-*-
package Para::Action::member_delete;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    # Authorization done in $m->remove

    my $mid = $q->param('mid')
	or throw('incomplete', "mid param missing");

    my $m = Para::Member->get_by_id( $mid );
    $m->remove;
    
    $q->delete('mid'); # Not existing anymore

    return "Medlemmen raderad";
}

1;
