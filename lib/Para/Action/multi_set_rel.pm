#  $Id$  -*-perl-*-
package Para::Action::multi_set_rel;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Arc;
use Para::Constants qw( $C_S_PROPOSED $C_TRUE_MIN );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 12 )
    {
	throw('denied', "Du måste bli gesäll för att få moderera relationer");
    }

    my $points = 0;

    foreach my $key ( $q->param )
    {
	next unless $key =~ /^relrev_(\d+)$/;

	my $id = $1;

	my $verdict = $q->param("relrev_${id}");
	next if $verdict eq '';

	warn sprintf "Checking relation $id\n";
	warn " verdict $verdict\n";

	my $arc = Para::Arc->get($id);

	my $pleed = $arc->strength < $C_TRUE_MIN ? 'f' : 't';

	warn sprintf "  %s\n", $arc->desig;
	warn "  pleed $pleed\n";

	if( $pleed eq $verdict )
	{
	    $arc->activate;
	}
	else
	{
	    $arc->deactivate;
	}

	$points ++;
    }

    return "$points relationer modererade!\n";
}

1;
