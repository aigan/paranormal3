#  $Id$  -*-cperl-*-
package Para::Action::cron_daily;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw debug get_from_fork );

use Para::Constants qw( $C_M_VIP );
use Para::Member;

sub handler
{
    my( $req, $event ) = @_;

    my $u = $req->s->u;
    if( $u->level < 42 )
    {
	throw('denied', "Reserverat för sysadmin");
    }

    debug "Running CRON DAILY";

    remove_member_level1();
    remove_member_level2();
    promote_member_level9();
    promote_member_level8();
    promote_member_level7();
    promote_member_level6();
    promote_member_level5();
    
#    clean_up_db();

    return "Klar";
}

sub remove_member_level1
{
    ### Remove persons that never logged in
    debug "* remove_member_level1";

    my $recs = $Para::dbix->select_list("select member from member where member_level = 1 and member > ? and age(member_created) > '14 days' and member_comment_admin is null", $C_M_VIP);

    foreach my $rec (@$recs)
    {
	my $m = Para::Member->get( $rec->{'member'} );
	next if $m->topic;
	$m->remove;
    }
}

sub remove_member_level2
{
    debug "* remove_member_level2";

    # Members on level 2

    # takers: Not logged in in 6 months
    my $recs1 = $Para::dbix->select_list("select member from member where member_level = 2 and member > ? and age(latest_in) > '182 days' and member_comment_admin is null and member_payment_total = 0", $C_M_VIP);

    # givers: Not logged in in 2 years
    my $recs2 = $Para::dbix->select_list("select member from member where member_level = 2 and member > ? and age(latest_in) > '730 days' and member_comment_admin is null and member_payment_total > 0", $C_M_VIP);

    foreach my $rec (@$recs1, @$recs2)
    {
	my $m = Para::Member->get( $rec->{'member'} );
	next if $m->topic;
	$m->remove;
    }
}

sub promote_member_level5
{
    debug "* promote_member_level5";

    # Members on level 5
    # Contact internal=5, external=10

    # takers: having more than 40 positive interests
    my $recs1 = get_from_fork(sub{$Para::dbix->select_list("select member from member where member in (select member from member, intrest where intrest_member=member and member_level=5 and intrest>30 group by member having count(intrest_topic) > 40) and present_contact_public >= 5 and present_contact >= 10 and member_payment_total = 0")});

    # givers: having more than 20 positive interests
    my $recs2 =  get_from_fork(sub{$Para::dbix->select_list("select member from member where member in (select member from member, intrest where intrest_member=member and member_level=5 and intrest>30 group by member having count(intrest_topic) > 20) and present_contact_public >= 5 and present_contact >= 10 and member_payment_total > 0")});

    foreach my $rec (@$recs1, @$recs2)
    {
	my $m = Para::Member->get( $rec->{'member'} );
	$m->set_member_level(6);
    }
}

sub promote_member_level6
{
    debug "* promote_member_level6";

    # Members on level 6
    # Contact internal=15

    # takers 1: having at least 6 described interests
    my $recs1 = get_from_fork(sub{$Para::dbix->select_list("select member from member where member in (select member from member, intrest where intrest_member=member and member_level=6 and intrest_defined >= 50 and length(intrest_description)>= 40  group by member having count(intrest_topic) >= 6) and present_contact >= 15 and member_payment_total = 0")});

    # takers 2: having at least 40 defined interests
    my $recs2 = get_from_fork(sub{$Para::dbix->select_list("select member from member where member in (select member from member, intrest where intrest_member=member and member_level=6 and intrest_defined >= 75 group by member having count(intrest_topic) >= 40) and present_contact >= 15 and member_payment_total = 0")});

    # givers 1: having at least 3 described interests
    my $recs3 = get_from_fork(sub{$Para::dbix->select_list("select member from member where member in (select member from member, intrest where intrest_member=member and member_level=6 and intrest_defined >= 50 and length(intrest_description)>= 40  group by member having count(intrest_topic) >= 3) and present_contact >= 15 and member_payment_total > 0")});

    # givers 2: having at least 20 defined interests
    my $recs4 = get_from_fork(sub{$Para::dbix->select_list("select member from member where member in (select member from member, intrest where intrest_member=member and member_level=6 and intrest_defined >= 75 group by member having count(intrest_topic) >= 20) and present_contact >= 15 and member_payment_total > 0")});

    foreach my $rec (@$recs1, @$recs2, @$recs3, @$recs4)
    {
	my $m = Para::Member->get( $rec->{'member'} );
	$m->set_member_level(7);
    }
}

sub promote_member_level7
{
    debug "* promote_member_level7";

    # Members on level 7
    # Has an active member topic
    # Has a surname
    # At least one of following are true
    #  - more than one accepted direct relations from member topic
    #  - at least one accepted direct relation to the member topic
    #  - has created more than one active topic

    # takers: spent 48 hours online
    my $recs1 = $Para::dbix->select_list("select member from member JOIN t ON member_topic = t JOIN score ON member = score_member
  where
    member_level = 7
  and
    member_topic is not null
  and
    length( name_given ) > 1
  and
    t_active is true
  and
    length(t_text) > 0
  and
  (
      1 < (select count(rel_topic) from rel where rev=t and rel_active is true and rel_indirect is false and rel_status > 3)
    or
      exists (select rel_topic from rel where rel=t and rel_active is true and rel_indirect is false and rel_status > 3 )
    or
      1 < ( select count(t) from t where t_createdby=member and t_active is true )
  )
  and
    time_online > 259200
  and
    member_payment_total = 0
");

    # givers: spent 6 hours online
    my $recs2 = $Para::dbix->select_list("select member from member JOIN t ON member_topic = t JOIN score ON member = score_member
  where
    member_level = 7
  and
    member_topic is not null
  and
    length( name_given ) > 1
  and
    t_active is true
  and
    length(t_text) > 0
  and
  (
      1 < (select count(rel_topic) from rel where rev=t and rel_active is true and rel_indirect is false and rel_status > 3)
    or
      exists (select rel_topic from rel where rel=t and rel_active is true and rel_indirect is false and rel_status > 3 )
    or
      1 < ( select count(t) from t where t_createdby=member and t_active is true )
  )
  and
    time_online > 43200
  and
    member_payment_total > 0
");

    foreach my $rec (@$recs1, @$recs2)
    {
	my $m = Para::Member->get( $rec->{'member'} );
	$m->set_member_level(8);
    }
}

sub promote_member_level8
{
    debug "* promote_member_level8";

    # Members on level 8
    # Contatc public=15

    # Takers:
    # member topic has more than 8 rels
    # has created more than 6 topics
    # Has spent more than 3 days online
    my $recs1 = $Para::dbix->select_list("select member from member JOIN t ON member_topic = t JOIN score ON member = score_member
  where
    member_level = 8
  and
    present_contact_public >= 15
  and
    t_active is true
  and
    8 < (select count(rel) from rel where rel=t and rel_active is true and rel_indirect is false and rel_status > 3 )
  and
    6 < ( select count(t) from t where t_createdby=member and t_active is true )
  and
    time_online > 345600
  and
    member_payment_total = 0
");

    # Givers:
    # member topic has more than 3 rels
    # has created more than 2 topics
    # Has spent more than 12 hours online
    my $recs2 = $Para::dbix->select_list("select member from member JOIN t ON member_topic = t JOIN score ON member = score_member
  where
    member_level = 8
  and
    present_contact_public >= 15
  and
    t_active is true
  and
    3 < (select count(rel) from rel where rel=t and rel_active is true and rel_indirect is false and rel_status > 3 )
  and
    2 < ( select count(t) from t where t_createdby=member and t_active is true )
  and
    time_online > 43200
  and
    member_payment_total > 0
");

    foreach my $rec (@$recs1, @$recs2)
    {
	my $m = Para::Member->get( $rec->{'member'} );
	$m->set_member_level(9);
    }
}

sub promote_member_level9
{
    debug "* promote_member_level9";

    # Member on level 9
    # Contatc public=15
    # Has been a member at least 90 days

    # Takers:
    # member topic has more than 10 rels
    # has created more than 40 topics
    # Has spent mor then 4 days online
    my $recs1 = $Para::dbix->select_list("select member from member JOIN t ON member_topic = t JOIN score ON member = score_member
  where
    member_level = 9
  and
    present_contact_public >= 15
  and
    t_active is true
  and
    10 < (select count(rel) from rel where rel=t and rel_active is true and rel_indirect is false and rel_status > 3 )
  and
    40 < ( select count(t) from t where t_createdby=member and t_active is true )
  and
    time_online > 432000
  and
    now() - member_created > interval '90 days'
  and
    member_payment_total = 0
");

    # Givers:
    # member topic has more than 5 rels
    # has created more than 20 topics
    # Has spent mor then 2 days online
    my $recs2 = $Para::dbix->select_list("select member from member JOIN t ON member_topic = t JOIN score ON member = score_member
  where
    member_level = 9
  and
    present_contact_public >= 15
  and
    t_active is true
  and
    5 < (select count(rel) from rel where rel=t and rel_active is true and rel_indirect is false and rel_status > 3 )
  and
    20 < ( select count(t) from t where t_createdby=member and t_active is true )
  and
    time_online > 172800
  and
    now() - member_created > interval '90 days'
  and
    member_payment_total > 0
");

    foreach my $rec (@$recs1, @$recs2)
    {
	my $m = Para::Member->get( $rec->{'member'} );
	$m->set_member_level(10);
    }
}

sub clean_up_db
{


}

1;

__END__


    ### Disable aliases for inactive topics
    # NOTE: We want to keep the aliases active even if the topic is
    # inactive
    #
    $Para::dbh->do("update talias set talias_status=0, talias_active='f' where talias_active is true and talias_t not in (select t from t where t=talias_t and t_active is true)");

    ### Remove empty aliases
    # NOTE: Not a problem any more?
    #
    $Psi::dbh->do("delete from talias where talias=''");

    ### Remove rels pointing to/from inactive topics
    # NOTE: should only update inacite rels. And do it by method calls
    #
    my $st  = qq{
	update rel set rel_status=0, rel_active='f', rel_updated=now(), rel_changedby = -1 where
	    (not exists ( select 1 from t where t=rev))
	    or
	    (rel is not null and not exists ( select 1 from t where t=rel))
	    or
	    (rel_status > 1 and not exists ( select 1 from t where t=rev and t_active is true))
	    or
	    (rel is not null and rel_status > 1 and not exists ( select 1 from t where t=rel and t_active is true))
	};

    ### Move lost entries to Lost entry
    # NOTE: Hopefully not needed anymore...
    my $st3 = "update t set t_entry_parent = 137624 where t_active and t in (select t from t as y where t_active and t_entry and t_entry_parent is null and not exists (select t from t where t_active is true and t_entry_next = y.t))";
