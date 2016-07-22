# -*-cperl-*-
package Para::Action::arc_delete;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Arc;

sub handler
{
	my( $req ) = @_;

	my $q = $req->q;
	my $u = $req->s->u;

	if ( $u->level < 12 )
	{
		throw('denied', "Du måste vara minst nivå 12");
	}

	my $rel_topic = $q->param('rel_topic')
		or throw('incomplete', "rel_topic param missing");

	my $arc = Para::Arc->get( $rel_topic ) or die "Arc $rel_topic not found";

	$arc->remove;



	clear_params(qw( rel_topic rel_type rel ));

	return "De nya uppgifterna har sparats";
}

1;
