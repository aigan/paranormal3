# -*-cperl-*-
package Para::Action::topic_delete;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Topic;

sub handler
{
	my( $req ) = @_;

	my $q = $req->q;
	my $u = $req->s->u;

	if ( $u->level < 40 )
	{
		throw('denied', "Reserverat för mästare");
	}

	my $tid = $q->param('tid')
		or throw('incomplete', "tid param missing");

	my $ver = $q->param('v')
		or throw('incomplete', "v param missing");

	my $t = Para::Topic->get_by_id( $tid, $ver );
	my $creator = $t->created_by;

	$t->delete_cascade;

	$u->score_change( 'rejected_thing', 1 );
	$creator->score_change('thing_rejected', 1 ) if $creator;

	$q->delete('tid');

	return "Ämnet $tid raderat";
}

1;
