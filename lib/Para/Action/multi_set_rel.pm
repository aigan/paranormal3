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
	next unless $key =~ /^relrev_(\d+)_(\d+)_(\d+)$/;

	my $reltype = $1;
	my $rel = $2;
	my $rev = $3;
	my $verdict = $q->param("relrev_${reltype}_${rel}_${rev}");
	next if $verdict eq '';

	warn sprintf "Checking relation R$reltype($rev,$rel)\n";
	warn " verdict $verdict\n";

	my $list = $Para::dbix->select_list('from rel where rev=? and rel_type=? and rel=?
                                and (rel_status>=? or rel_active is true)
                                order by rel_topic', $rev, $reltype, $rel,
			       $C_S_PROPOSED);

	my $active_seen = 0; # Set if any in the list is active.  Just one in the list should bee
	foreach my $rec ( @$list ) ## In creation order
	{
	    my $pleed = $rec->{'rel_strength'} < $C_TRUE_MIN
	      ? 'f' : 't';

	    my $arc = Para::Arc->get( $rec->{'rel_topic'}, $rec );

	    warn sprintf "  %s\n", $arc->desig;
	    warn "  pleed $pleed\n";


	    if( $pleed eq $verdict )
	    {
		warn "  Activating this?\n";
		if( not $active_seen )
		{
		    $active_seen = 1;
		    $arc->activate;
		}
	    }
	    else
	    {
		$arc->deactivate;
	    }
	    $points ++;
	}
    }

    return "$points relationer modererade!\n";
}

1;
