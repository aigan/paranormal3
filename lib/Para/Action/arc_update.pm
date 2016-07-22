# -*-cperl-*-
package Para::Action::arc_update;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Arc;

sub handler
{
	my( $req ) = @_;

	my $q = $req->q;
	my $u = $req->s->u;

	if ( $u->level < 10 )
	{
		throw('denied', "Du måste vara minst nivå 10");
	}

	my $rel_topic = $q->param('rel_topic')
		or throw('incomplete', "rel_topic param missing");

	my $arc = Para::Arc->get( $rel_topic ) or die "Arc not found";
	my $new_pred = Para::Arctype->new( $q->param('rel_type') );

	my $new_rev_topic = Para::Topic->find_one( $q->param('rev') );
	my $new_objvalue = $q->param('rel');
	my $new_comment = $q->param('rel_comment') || '';


	$arc->replace( $new_pred, $new_rev_topic, $new_objvalue,
								 {
									comment => $new_comment,
									true    => $arc->true,
									active  => $arc->active,
								 });

	return "Arc $rel_topic har uppdaterats";
}

1;
