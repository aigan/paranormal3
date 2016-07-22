# -*-cperl-*-
package Para::Action::topic_vacuum;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Topic;

sub handler
{
	my( $req ) = @_;

	my $q = $req->q;
	my $u = $req->s->u;

	if ( $u->level < 12 )
	{
		throw('denied', "Enbart för väktare");
	}

	my $tid = $q->param('tid') || $q->param('eid')
		or throw('incomplete', "tid/eid param missing\n");

	my $t = Para::Topic->get_by_id( $tid );
	$t->vacuum;

	return "Ämnet städat\n";
}

1;
