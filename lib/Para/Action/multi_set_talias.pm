#  $Id$  -*-perl-*-
package Para::Action::multi_set_talias;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw clear_params );

use Para::Topic;
use Para::Constants qw( $C_S_DENIED );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 12 )
    {
	throw('denied', "Du måste bli gesäll för att få moderera aliases");
    }

    my $changed = 0;
    my @clear_fields = ();

    for( my $row=1; my $talias = $q->param("_talias__${row}_talias"); $row++ )
    {
	warn "Checking $row, $talias\n";
	push @clear_fields, "_talias__${row}_talias", "_talias__${row}_keep", "_talias__${row}_topic", "_talias__${row}_talias_autolink", "_talias__${row}_talias_index";

	my $tid = $q->param("_talias__${row}_topic")
	    or die "no topic for $row\n";

	my $a = Para::Topic->get_by_id($tid)->alias( $talias ) or die;

	my $verdict = $q->param("_talias__${row}_keep")||'';

	if( $verdict eq 't' )
	{
	    my $autolink = $q->param("_talias__${row}_talias_autolink");
	    my $index = $q->param("_talias__${row}_talias_index");
	    my $language = $q->param("_talias__${row}_talias_language");
#	    $language ||= undef;

	    $a->update({
			autolink => $autolink,
			index    => $index,
			language => $language,
			status   => $u->new_status,
		       });
	    warn "  change\n";
	    $changed ++;
	}
	elsif( $verdict eq 'f' )
	{
	    $a->update({
			status => $C_S_DENIED,
		       });
	    warn "  remove\n";
	    $changed ++;
	}
    }


    # Nothing changed
    return "" unless $changed;

    clear_params(@clear_fields);

    return "$changed alias modererade";
}

1;
