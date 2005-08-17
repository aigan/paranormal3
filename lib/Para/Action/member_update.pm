#  $Id$  -*-perl-*-
package Para::Action::member_update;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw debug );

use Para::Member;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

#    warn Dumper $q;

    my $mid = $q->param('mid') or throw('incomplete', "member param missing\n");
    my $m = Para::Member->get( $mid );

    # Comply to this to get access
    unless( ($u->level >= 41) or ($u->id == $mid) or ($mid > 1000 and $m->level <= 1)  )
    {
	throw('denied', "Du har inte access för att ändra någon annan.");
    }

    $m->changes->reset;

    # Meta-fields
    #
    if( my $val = $q->param('_meta_theory_practice') )
    {
	$q->param('general_theory',(100-$val));
	$q->param('general_practice',$val);
    }
    if( my $val = $q->param('_meta_meeter_bookmark') )
    {
	$q->param('general_meeter',(100-$val));
	$q->param('general_discussion',(100-$val));
	$q->param('general_bookmark',$val);
    }
    if( my $val = $q->param('_meta_present_contact') )
    {
	$q->param('present_contact', $val);
	$q->param('present_contact_public', $val);
    }

    ### _meta_mailalias
    #
    my $_meta_mailalias = $q->param('_meta_mailalias');
    if( defined $_meta_mailalias )
    {
	$m->set_mailaliases([  split /\n/, $_meta_mailalias ]);
    }

    ### Do the big part of the job right here
    #
    $m->update_by_query;


    $m->mark_publish;

    ## Commit changes
    $Para::dbh->commit;


    # Sync with u  (is this needed?)
    #
    if( $mid == $u->id )
    {
	$u = $Para::Frame::CFG->{'user_class'}->identify_user();
    }


    if( $q->param('done_presentation') )
    {
	if( length($q->param('presentation')) < 300 )
	{
	    throw('validation', "Din presentation kommer att läsas igenom av en människa.\n".
		  "Du har skrivit för lite.  Skriv några rader till.\n".
		  "Om du vill kan då återkomma imorgon och fortsätta.\n".
		  "Det du skrivit hittills kommer att finnas kvar imorgon.\n".
		  "Presentation behövs för att bli medborgare, men du måste\n".
		  "inte vara medborgare för att läsa i uppslagsverket.");
	}

	# Promote member to level 3 if all is OK
	#
	my $statement = "update member set
                         member_level=?, member_updated=now()
                         where member=? and member_level=2";
	my $sth = $Para::dbh->prepare( $statement );
	$sth->execute( 3, $m->id );
	$m->{'member_level'} = 3;
	$Para::dbh->commit;

	$m->change->success("Välkommen till nivå 3");
    }

    $m->change->report;

    debug(4,"User is: ".$u->desig);

    return "";
}

1;
