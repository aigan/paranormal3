# -*-cperl-*-
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

	if ( $u->level < 12 )
	{
		throw('denied', "Du måste bli väktare för att få flytta texter");
	}

	# Moves tid --> t2_id

	my $tid1 = $q->param('tid') or die "Param tid missing";
	my $tid2 = $q->param('t2_id') or throw('incomplete', "Du har inte markerat vart du vill flytta texten");

	my $t1 = Para::Topic->get_by_id($tid1); # Should be entry
	my $t2 = Para::Topic->get_by_id($tid2);

	# Moves t1 --> t2

	# Check things
	unless( $t1->entry )
	{
		throw('validation', "t1 must be entry");
	}

	# Returns the new version
	$t1 = $t1->create_new_version unless $q->param('keep_version');

	my $result = "";

	if ( $q->param('move_node') )
	{
		$result .= $t1->move_node( $t2 );
	}
	else
	{
		$result .= $t1->move_branch( $t2 );
	}

	$t1->generate_url;

	$q->param('tid', $tid2);

	return $result;
}

1;
