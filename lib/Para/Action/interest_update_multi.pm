#  $Id$  -*-perl-*-
package Para::Action::interest_update_multi;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw maxof inflect );

use Para::Member;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;
    my $db = $Para::dbix;


    my $mid = $q->param('mid') or throw('incomplete', "mid param missing\n");

    if( $u->level < 40 and $u->id != $mid )
    {
	throw('denied', "Du har inte access för att ändra någon annans intressen.");
    }

    my $m = Para::Member->get($mid);

    my $belief     = $m->{'general_belief'}      || 0;
    my $theory     = $m->{'general_theory'}      || 5;
    my $practice   = $m->{'general_practice'}    || 5;
    my $editor     = $m->{'general_editor'}      || 0;
    my $helper     = $m->{'general_helper'}      || 5;
    my $meeter     = $m->{'general_meeter'}      || 5;
    my $bookmark   = $m->{'general_bookmark'}    || 5;
    my $discussion = $m->{'general_discussion'}  || 5;

    my $interest_count = 0;
    my $disinterest_count = 0;
    my $topic_count = 0;

    foreach my $field ( $q->param() )
    {
	warn "  Testing $field\n";
	if( $field =~ /^_meta_interest_(\d+)$/ )
	{
	    my $tid = $1;
	    $topic_count ++;

	    my $interest = $q->param($field)/100;
	    if( $q->param($field) > 50 )
	    {
		$interest_count ++;
	    }
	    else
	    {
		$disinterest_count ++;
	    }

	    warn "    Defining interest $tid\n";

	    my $i = $m->interest($tid);

	    my $rec =
	    {
		belief => $belief * $interest,
		practice => $practice * $interest,
		theory   => $theory * $interest,
		knowledge => $theory * $interest / 3,
		editor => $editor * $interest,
		helper => $helper * $interest,
		meeter => $meeter * $interest,
		bookmark => $bookmark * $interest,
		interest => $q->param($field),
		defined => maxof($i->defined, 10),
	    };

	    $i->update($rec);
	}
    }

    # Check interests for sanity
    #
    if( $q->param('interest_sanity') )
    {
	$interest_count or throw('validation',
			       "Det måste väl vara något du är extra intresserad av?!?\n");
	$disinterest_count or throw('validation',
				  "Du kan väl inte vara intresserad av allt?!?\n");
    }



    my $tid = $q->param('tid');
    if( $tid )
    {
	warn "    Updating interest in $tid\n";
	$m->interest($tid)->update_by_query()
    }

    return( "Antal intressen uppdaterade: ".
	    inflect( $interest_count,
		     "Inga nya intressen, men ",
		     "Ett nytt intresse och ",
		     "%d nya intressen och ").
	    inflect( $disinterest_count,
		     "inga o-intressen",
		     "ett o-intresse",
		     "%d o-intressen")
	    );
}

1;
