package Para::Action::member_update;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

#use Para::Common qw( identify_user );
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

    $m->changes_reset;

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
    if( my $val = $q->param('_meta_mailalias') )
    {
	$m->set_mailaliases([  split /\n/, $val ]);
    }

    foreach my $field ( qw( nickname home_online_msn home_online_uri
			    sys_email bdate_ymd_year member_level
			    gender name_given name_middle name_family
			    home_postal_code home_tele_phone
			    home_tele_mobile home_tele_fax
			    present_contact present_contact_public

			    ) )
    {
	if( defined $q->param($field) )
	{
	    $m->set($field, $q->param($field));
	}
    }

    foreach my $field ( qw( name_prefix name_suffix home_postal_name
			    home_postal_street home_postal_visiting
			    home_tele_phone_comment
			    home_tele_mobile_comment
			    home_tele_fax_comment statement style
			    home_online_email presentation
			    member_comment_admin show_style

			    ) )
    {
	if( defined $q->param($field) )
	{
	    $m->set_field($field, $q->param($field));
	}
    }

    foreach my $field ( qw( home_online_icq home_online_aol
				 sys_logging present_intrests
				 present_activity present_gifts general_belief
				 general_theory general_practice
				 general_editor general_helper
				 general_meeter general_bookmark
				 general_discussion show_complexity
				 show_detail show_edit show_level newsmail
				 member_topic chat_level ) )

    {
	if( defined $q->param($field) )
	{
	    $m->set_field_number($field, $q->param($field));
	}
    }

    $m->mark_publish;

    ## Commit changes
    $Para::dbh->commit;


    # Sync with u  (is this needed?)
    #
    if( $mid == $u->id )
    {
	Para::Frame::User->identify_user();
    }


    if( $q->param('done_presentation') )
    {
	if( length($q->param('presentation')) < 300 )
	{
	    throw('validation', "Du har skrivit för lite.  Skriv några rader till.\n".
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
	my $sth = $Para::dbh->prepare_cached( $statement );
	$sth->execute( 3, $m->id );
	$m->{'member_level'} = 3;
	$Para::dbh->commit;

	$m->change->success("Välkommen till nivå 3");
    }

    my $change = $m->change;
    if( $change->changes )
    {
	$req->result->message( $change->message );
    }

    if( $change->errors )
    {
	throw('validation', $change->errmsg );
    }

    return "";
}

1;
