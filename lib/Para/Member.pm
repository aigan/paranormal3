#  $Id$  -*-perl-*-
package Para::Member;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Member class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2005 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Data::Dumper;
use Mail::Address;
use Carp;
use Time::Seconds;
use locale;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Time qw( now date duration );
use Para::Frame::Utils qw( throw trim passwd_crypt paraframe_dbm_open make_passwd debug uri );
use Para::Frame::Email;
use Para::Frame::Change;

use Para::Topic;
use Para::Interests;
use Para::Interest;
use Para::Constants qw( :all );
use Para::Mailbox;
use Para::Arc;
use Para::Payment;
use Para::Email::Address;
use Para::Member::Email::Address;
use Para::Place;
use Para::Utils qw( trim_text );

use base qw( Para::Frame::User );
use base qw( Exporter );

BEGIN
{
    our @EXPORT_OK = qw( name2nick name2chat_nick trim_name );

}

our $ONLINE_COUNT; # Not used, since $C_DB_ONLINE changes externally
our %UNSAVED;

 INIT:
{
    my $rec = 
    {
	'member'        => 0,
	'nickname'      => 'guest',
	'member_level'  => 0,
	'name_given'    => 'Gäst',
    };
    $Para::Member::CACHE->{0} = bless($rec, __PACKAGE__);

}

sub skapelsen
{
    return $Para::Member::CACHE->{-1} ||= $_[0]->get_by_id(-1);
}

sub become_root
{
    debug(3,"Becoming root");
    return $_[0]->become_temporary_user( $_[0]->skapelsen );
}

sub become_unpriviliged_user
{
    debug(3,"Becoming John Doe");
    my $john_doe = Para::Member->get( 46 );
    return $_[0]->become_temporary_user( $john_doe );
}

sub get
{
    my( $this, $member_in ) = @_;

    carp "No member info" unless $member_in;
    if( ref $member_in )
    {
	return $member_in;
    }
    elsif( $member_in =~ /^-?\d+$/ )
    {
	return $this->get_by_id( $member_in );
    }
    else
    {
	# No censor default, to make it compatible with Para::Frame::User
	return $this->get_by_nickname( $member_in, 0 );
    }
}

sub get_by_id
{
    my( $this, $mid, $rec, $no_cache ) = @_;
    my $class = ref($this) || $this;


#    debug "get member by id $mid";
    # $rec can be provided as a mean for optimization

    return undef unless defined $mid;
    return $mid if ref $mid eq 'Para::Member';
    confess "mid not a number: $mid" unless $mid =~ /^-?\d+$/;

    # If we should use the cache
    if( not $no_cache )
    {
	if( $Para::Member::CACHE->{$mid} )
	{
	    return $Para::Member::CACHE->{$mid};
	}
    }

    return $Para::Member::CACHE->{0} if $mid == 0;

    if( $rec )
    {
	## Merge with passwd record if not yet done
	#
	unless( $rec->{'passwd_member'} )
	{
	    my $st = "select * from passwd where passwd_member=?";
	    my $sth = $Para::dbh->prepare( $st );
	    $sth->execute( $mid );
	    my $pwrec = $sth->fetchrow_hashref
		or die "failed to get $mid passwd";
	    $sth->finish;

	    foreach my $key ( keys %$pwrec )
	    {
		$rec->{$key} = $pwrec->{$key};
	    }
	}
    }
    else
    {
	my $st = "select * from member LEFT JOIN passwd ON member=passwd_member where member=?";
	my $sth = $Para::dbh->prepare( $st );
	$sth->execute( $mid );
	$rec =  $sth->fetchrow_hashref;
	$sth->finish;
    }

    if( $rec )
    {
	if( $no_cache )
	{
	    debug(4, "Got member $mid, bypassing cache");
	    return bless($rec, $class);
	}
	else
	{
	    debug(4, "Initiated member $mid");
	    return $Para::Member::CACHE->{$mid} = bless($rec, $class);
	}
    }
    else
    {
	$Para::Member::CACHE->{$mid} = undef;
	return Para::Member->get_by_id(-2); # Old member
    }
}

sub get_by_tid
{
    my( $this, $tid ) = @_;
    my $class = ref($this) || $this;

    return undef unless defined $tid;

    my $st = "select * from member LEFT JOIN passwd ON member=passwd_member where member_topic=?";
    my $sth = $Para::dbh->prepare( $st );
    $sth->execute( $tid );
    my $rec =  $sth->fetchrow_hashref;
    $sth->finish;

    return undef unless $rec;
    return $this->get_by_id( $rec->{'member'}, $rec );
}

sub get_by_nickname
{
    my( $class, $identity, $censor, $no_cache ) = @_;

    trim( \$identity );
    $identity = lc( $identity );
    my $nick = name2nick( $identity );

    debug(3,"Get member $nick");

#    # Bootstrap user
#    $Para::Frame::U ||= $Para::Member::CACHE->{0};

    return $Para::Member::CACHE->{0} if $nick eq 'guest';

    $censor = 1 unless defined $censor;

    if( $nick eq 'mig' )
    {
	$nick = $Para::Frame::U->id;
    }

    unless( $no_cache )
    {
	if( $Para::Member::CACHE->{$nick} )
	{
	    return $Para::Member::CACHE->{$nick};
	}
    }


    my $censor_part = "";
    if( $censor and $Para::Frame::U->level < 41)
    {
	$censor_part .= " and present_contact > 1";
	$censor_part .= " and member_level > 0";
    }


    if( $nick =~ m/^\d+$/ )
    {
	my $st = "select * from member LEFT JOIN passwd ON member=passwd_member where member=? $censor_part";
	my $sth = $Para::dbh->prepare( $st );
	$sth->execute( $nick );
	my $rec =  $sth->fetchrow_hashref;
	$sth->finish;
	if( $rec )
	{
	    my $m =$class->get_by_id($rec->{'member'}, $rec, $no_cache);
	    return undef if $censor_part and $m->present_contact<5;
	    return $m;
	}
	return undef;
    }
    else
    {
	my $st = "select * from nick JOIN member ON nick_member=member LEFT JOIN passwd ON member=passwd_member where uid=? $censor_part";
	my $sth = $Para::dbh->prepare( $st );
#	warn "  Executing $st ($nick)\n" if $DEBUG;
	$sth->execute( $nick );
	my $rec =  $sth->fetchrow_hashref;
	$sth->finish;
	if( $rec )
	{
	    my $m = $Para::Member::CACHE->{$nick} =
	      $class->get_by_id($rec->{'member'}, $rec, $no_cache);
	    return undef if  $censor_part and $m->present_contact<5 and $nick ne $m->nickname;
	    return $m;
	}
	return undef;
    }
}

######################


sub create
{
    my( $this, $nick ) = @_;
    my $class = ref($this) || $this;

    trim_name(\$nick);
    my $uid = name2nick($nick);
    my $chat_nick = name2chat_nick($nick);

    Para::Member->validate_nick( $uid );

    my $mid = $Para::dbix->get_nextval( "member_seq" );

    my $sth_nick = $Para::dbh->prepare("insert into nick
                                   ( uid, nick_member, nick_created )
                                   values ( ?, ?, now())");

    $sth_nick->execute( $uid, $mid );

    my $sth_member = $Para::dbh->prepare("insert into member
               ( member, nickname, chat_nick, member_level, member_created, member_updated, present_contact, present_intrests, present_activity, sys_logging, geo_precision )
               values ( ?, ?, ?, 1, now(), now(), 15, 30, 10, 30, 0 )");
    $sth_member->execute($mid, $nick, $chat_nick);
	
    my $sth_score = $Para::dbh->prepare("insert into score
               ( score_member ) values ( ? )");
    $sth_score->execute($mid);
	
    my $passwd = make_passwd();
    my $sth_passwd = $Para::dbh->prepare("insert into passwd
               ( passwd_member, passwd, passwd_updated, passwd_changedby )
               values ( ?, ?, now(), -1 )");
    $sth_passwd->execute($mid, $passwd);
	
    my $m = $this->get_by_id( $mid );
    $m->change->success("Medlemskap registrerat");

    

    return $m;
}

##################################################

sub verify_password
{
    my( $m, $password_encrypted ) = @_;

    $password_encrypted ||= '';

    my $now = now();

    # Update login time
    if( $m->offline )
    {
	$m->latest_in( $now );
    }

    $m->latest_seen( $now );

    if( $password_encrypted eq passwd_crypt($m->{'passwd'}) )
    {
	return 1;
    }
    else
    {
	my $expected = passwd_crypt($m->{'passwd'});
	debug(1,"Expected $expected but got $password_encrypted");
	foreach my $key ( keys %ENV )
	{
	    debug "  $key : $ENV{$key}";
	}
	return 0;
    }
}

sub on_login
{
    my( $u ) = @_;

    # Promote user if this is the first login
    #
    if( $u->level == 1 )
    {
	my $sys = Para::Member->get(-1);
	$u->level( 2, $sys );
	my $req = $Para::Frame::REQ;
	$req->page->set_template("/member/db/person/quest/level_02/welcome.tt");
	$u->changes->report;
    }
}

sub on_logout
{
    my( $u, $time ) = @_;

    $time ||= now();
    $u->latest_out( $time ) if $u->level > 0; # In case user deleted
    my $db = paraframe_dbm_open( $C_DB_ONLINE );
    delete $db->{$u->id};
}

sub set
{
    my( $m, $field, @args ) = @_;

    no strict qw( refs );
    return &{"set_$field"}($m, @args);
}

sub set_field
{
    my( $m, $field, $value ) = @_;

    return unless defined $value;
    trim(\$value);
    $m->{$field} ||= '';
    return if $value eq $m->{$field};
    $m->{$field} = $value;
    $m->mark_unsaved;
    return $m->change->success("$field uppdaterad");
}

sub set_field_block
{
    my( $m, $field, $value ) = @_;

    return unless defined $value;
    trim_text(\$value);
    $m->{$field} ||= '';
    return if $value eq $m->{$field};
    $m->{$field} = $value;
    $m->mark_unsaved;
    return $m->change->success("$field uppdaterad");
}

sub set_field_number
{
    my( $m, $field, $value ) = @_;

    return unless defined $value;
    trim(\$value);
    return if $m->{$field} and $value eq $m->{$field};
    if( length $value )
    {
	unless( $value =~ /^-?\d+$/ )
	{
	    return $m->change->fail("$field tillåter bara nummer");
	}
    }
    $m->{$field} = $value;
    $m->mark_unsaved;
    return $m->change->success("$field uppdaterad");
}



sub set_passwd
{
    my( $m, $old, $new, $confirm ) = @_;
    trim(\$old);
    trim(\$new);
    trim(\$confirm);
    return if $m->{'passwd'} eq $new;

    my $req = $Para::Frame::REQ;
    my $mid = $m->id;
    my $q = $req->q;
    my $u = $req->s->u;

    my $admin = $u->level >= 41 ? 1:0;

    if( not $admin and not $m->verify_password( passwd_crypt $old ) )
    {
	return $m->change->fail("Det gamla lösenordet stämde inte\n");
    }

    debug(1,"Trying to change passwd to '$new'");
    length($new) >= 4 or return $m->change->fail("Lösenordet är för kort. Använd åtminstonne 4 tecken\n");
    length($new) <= 12 or return $m->change->fail("Lösenordet är för långt. Använd som mest 12 tecken\n");
    $new =~ /^[\x21-\x7e]+$/ or return $m->change->fail("Lösenordet har ogiltiga tecken.\n".
							"(Använd ASCII x21-x74 (Allting utom mellanslag (och åäö))\n");

    if( $new ne $confirm )
    {
	return $m->change->fail("De två lösenorden stämde inte överens\n");
    }

    my $now = now();

    $Para::dbix->update('passwd',
			{
			    passwd_updated => $now,
			    passwd_changedby => $u->id,
			    passwd_previous => $m->{'passwd'},
			    passwd => $new,
			},
			{
			    passwd_member => $mid,
			});

    $m->{'passwd_updated'} = $now;
    $m->{'passwd_changedby'} = $u;
    $m->{'passwd_previous'} = $m->{'passwd'};
    $m->{'passwd'} = $new;

    $m->set_dbm_passwd;

    if( $mid == $u->id )
    {
	# Update cookie for new password
	#
	$req->cookies->add({'password' => passwd_crypt($new) });
    }

    return $m->change->success("Nytt lösenord lagrat");
}

sub password
{
    my( $m ) = @_;
    my $req = $Para::Frame::REQ;
    my $u = $req->s->u;
    my $admin = $u->level >= 41 ? 1:0;

    unless( $admin )
    {
	throw('denied', "Lösenord är hemliga");
    }

    return $m->{'passwd'};
}


##################################################

sub id       { shift->{'member'} }
sub uid      { shift->{'member'} } # Used by Para::Frame::User


sub update_by_query
{
    my( $m ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

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
			    home_tele_fax_comment statement
			    home_online_email show_style
			    home_online_skype
			    ) )
    {
	if( defined $q->param($field) )
	{
	    $m->set_field($field, $q->param($field));
	}
    }

    foreach my $field ( qw( presentation
			    member_comment_admin
			    ) )
    {
	if( defined $q->param($field) )
	{
	    $m->set_field_block($field, $q->param($field));
	}
    }

    foreach my $field ( qw( home_online_icq home_online_aol
				 sys_logging present_intrests
				 present_activity present_gifts
				 present_blog general_belief
				 general_theory general_practice
				 general_editor general_helper
				 general_meeter general_bookmark
				 general_discussion show_complexity
				 show_detail show_edit show_level
				 newsmail member_topic chat_level ) )

    {
	if( defined $q->param($field) )
	{
	    $m->set_field_number($field, $q->param($field));
	}
    }

    $m->mark_updated;
}

sub show_complexity
{
    return $_[0]->{'show_complexity'};
}

sub complexity
{
    return $_[0]->{'show_complexity'}||0;
}

sub show_level
{
    return $_[0]->{'show_level'};
}

sub show_style
{
    return $_[0]->{'show_style'};
}

sub style
{
    return $_[0]->{'show_style'};
}

sub presentation   { shift->{'presentation'} }

sub sys_uid   { shift->{'sys_uid'} }
sub set_sys_uid
{
    my( $m, $nick ) = @_;

    $nick ||= $m->_nickname;
    my $sys_uid = name2nick($nick);
    unless( $m->has_nick( $sys_uid ) )
    {
	return $m->change->fail("Namnet '$nick' liknar inte något av dina alias\n");
    }

    $m->set_field( 'sys_uid' => $sys_uid );
    $m->update_mail_forward;
    $m->set_dbm_passwd;
    $m->mailbox->create;
    return $m->{'sys_uid'};
}

sub unset_sys_uid
{
    my( $m ) = @_;

    $m->{'sys_uid'} = undef;
    $m->mark_updated;
    return 1;
}

sub present_contact   { shift->{'present_contact'} ||0 }
sub present_contact_public { shift->{'present_contact_public'} ||0 }
sub present_activity  { shift->{'present_activity'} ||0 }
sub present_interests { shift->{'present_intrests'} ||0  }
sub present_gifts { shift->{'present_gifts'} ||0 }
sub present_blog { shift->{'present_blog'} ||0 }

sub topic
{
    my $tid =  shift->{'member_topic'};
    return undef unless $tid;

    return Para::Topic->get_by_id( $tid );
}



sub interests
{
    my( $m ) = @_;

    unless( $m->{'interests'} )
    {
	# This will set upp all defined interests of the member
	$m->{'interests'} = Para::Interests->new( $m );
    }
    return $m->{'interests'};
}

sub interest
{
    my( $m, $t ) = @_;

    if( $m->equals($Para::Frame::U) )
    {
	return $m->interests->getset( $t );
    }
    else
    {
	return $m->interests->get( $t );
    }
}

sub title
{
    my( $m, $publ, $verbose ) = @_;

    # publ has the same rules as other
    $verbose ||= 0;

    # $Para::mtitle defined in constants

    if( $m->present_interests >= 5 or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $Para::mtitle->{ $m->level }[ $verbose ];
    }

    return undef;
}

sub file
{
    my( $m ) = @_;

    if( my $tid = $m->{'member_topic'} )
    {
	return Para::Topic->get_by_id( $tid )->file;
    }

    return undef;
}

sub link
{
    my( $m ) = @_;

    if( my $file = $m->file )
    {
	return &Para::Frame::Widget::jump( $m->{'nickname'}, $m->file );
    }
    else
    {
	return &Para::Frame::Widget::jump( $m->{'nickname'}, '/member/db/person/view', { mid => $m->id } );
    }
}

sub tlink  # Link to page with title. No link to adminpage
{
    my( $m ) = @_;

    if( my $file = $m->file )
    {
	return &Para::Frame::Widget::jump( $m->title .' '. $m->{'nickname'}, $m->file );
    }
    else
    {
	return $m->title .' '. $m->{'nickname'};
    }
}

sub mlink # Link to admin page. Relative $u
{
    my( $m, $called ) = @_;

    $called ||= 'Ditt';

    my $page = uri("/member/db/person/view/",
		   { mid => $m->id } );
    unless( $m->equals($Para::Frame::U) )
    {
	$called = $m->{'nickname'};
    }
    
    return &Para::Frame::Widget::jump( $called, $page );
}

sub geo_x
{
    my( $m ) = @_;
    return $m->{'geo_x'};
}

sub geo_y()
{
    my( $m ) = @_;
    return $m->{'geo_y'};
}

sub set_geo
{
    my( $m, $geo_x, $geo_y, $geo_precision ) = @_;

    # See also $m->zip2city()

    $geo_precision ||= 0;
    throw('validation', "geo_y not given") unless $geo_y;

    # TODO: Validate against zip if existing

    $m->{'geo_x'} = $geo_x;
    $m->{'geo_y'} = $geo_y;
    $m->{'geo_precision'} = $geo_precision;

    $m->mark_unsaved;
    return 1;
}

sub dist
{
    my( $m, $obj, $publ ) = @_;

    unless( $m->present_contact >= 15 or ($publ and
	    $m->present_contact_public >= 15) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return undef;
    }


    debug(0,"in dist m $m->{'geo_x'} n $obj->{'geo_x'}");
    if( UNIVERSAL::isa( $obj, 'Para::Member') and
	$m->{'geo_x'} and $obj->{'geo_x'})
    {
	my $scale = 70.86666666666; # km

	my $x = $m->{'geo_x'};
	debug(3,"x: $x");
	my $xdp = $x - $obj->{'geo_x'};
	debug(3,"xdp: $xdp");
	my $xd = $xdp * $scale;
	debug(3,"xd: $xd");

	my $y = $m->{'geo_y'};
	debug(3,"y: $y");
	my $ydp = $y - $obj->{'geo_y'};
	debug(3,"ydp: $ydp");
	my $yd = $ydp * $scale;
	debug(3,"yd: $yd");


	my $dist = sqrt($xd ** 2 + $yd ** 2);
	$dist =~ tr/,/./;
	debug(3,"dist is $dist");
	$dist = sprintf("%.1f", $dist);
	debug(3,"dist is $dist");
	return $dist;
    }

    return undef;
}

sub comment
{
    if( $Para::Frame::U->level >= 41 )
    {
	return shift->{'member_comment_admin'};
    }
    return "";
}

sub equals
{
    my( $m, $m2 ) = @_;

    return 0 unless ref $m2;
    if( $m->id == $m2->id )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub as_string
{
    shift->desig(@_);
}

sub desig
{
    my( $m, $publ ) = @_;
    # Set publ true if this will be given to the public

    return $m->name( $publ ) || $m->nickname( $publ );
}

sub sysdesig
{
    my( $m ) = @_;

    return $m->nickname;
}

sub name
{
    my( $m, $publ ) = @_;
    # Set publ true if this will be given to the public

    if( (not $publ and $m->present_contact >= 12) or ($publ and
	    $m->present_contact_public >= 11) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	my $first = $m->{name_given} || '';
	my $middle = $m->{name_middle} || '';
	my $last = $m->{name_family} || '';
	return undef unless length($first.$last);
	my $name = join ' ', $first, $middle, $last;
	$name =~ s/  +/ /g;
	return $name;
    }

    return undef;
}

sub name_given
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 12) or ($publ and
	    $m->present_contact_public >= 12) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $m->{name_given};
    }

    return undef;
}

sub name_middle
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 12) or ($publ and
	    $m->present_contact_public >= 12) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $m->{name_middle};
    }

    return undef;
}

sub name_family
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 12) or ($publ and
	    $m->present_contact_public >= 12) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $m->{name_family};
    }

    return undef;
}

sub age
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 5) or ($publ and
	    $m->present_contact_public >= 15) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return undef unless $m->{'bdate_ymd_year'};
	return now()->year - $m->{'bdate_ymd_year'};
    }
    return undef;
}

sub gender
{
    my( $m, $publ ) = @_;

    # M or F

    if( (not $publ and $m->present_contact >= 5) or ($publ and
	    $m->present_contact_public >= 5) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $m->{'gender'};
    }
    return undef;
}

sub city
{
    return shift->home_postal_city(@_);
}

sub home_postal_name
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 15) or ($publ and
	    $m->present_contact_public >= 15) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_postal_name'};
    }

    return undef;
}

sub home_postal_street
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 20) or ($publ and
	    $m->present_contact_public >= 20) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_postal_street'};
    }

    return undef;
}

sub home_postal_street_best_guess
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 20) or ($publ and
	    $m->present_contact_public >= 20) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	my $street = $m->{'home_postal_visiting'} ||
	    $m->{'home_postal_street'};
	my $code = $m->{'home_postal_code'};
	if( $code and not $street )
	{
	    $street = Para::Place->by_zip($code)->aproximate_street->name;
	}
	return $street;
    }

    return undef;
}

sub home_postal_county
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 15) or ($publ and
	    $m->present_contact_public >= 15) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	my $code = $m->{'home_postal_code'} or return undef;
	return Para::Place->by_zip($code)->county->name;
    }

    return undef;
}

sub home_postal_municipality
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 15) or ($publ and
	    $m->present_contact_public >= 15) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	my $code = $m->{'home_postal_code'} or return undef;
	return Para::Place->by_zip($code)->municipality->name;
    }

    return undef;
}

sub home_postal_city
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 15) or ($publ and
	    $m->present_contact_public >= 15) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_postal_city'};
    }

    return undef;
}

sub home_postal_code
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 15) or ($publ and
	    $m->present_contact_public >= 15) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $_[0]->{'home_postal_code'};
    }

    return undef;
}

sub home_online_email
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 5 and $m->newsmail > 0)
        or ($publ and $m->present_contact_public >= 5) or
        $Para::Frame::U->level >= 41 or $m->equals( $Para::Frame::U ) )
    {
	return $_[0]->{'home_online_email'};
    }

    return undef;
}

sub home_online_uri
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 5) or ($publ and
        $m->present_contact_public >= 5) or $Para::Frame::U->level >= 41 or
        $m->equals( $Para::Frame::U ) )
    {
	return $_[0]->{'home_online_uri'};
    }

    return undef;
}

sub home_online_icq
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 5) or ($publ and
	$m->present_contact_public >= 5) or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_online_icq'};
    }

    return undef;
}

sub home_online_skype
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 5) or ($publ and
	$m->present_contact_public >= 5) or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_online_skype'};
    }

    return undef;
}

sub home_online_msn
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 5) or ($publ and
	$m->present_contact_public >= 5) or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_online_msn'};
    }

    return undef;
}

sub general_belief
{
    my( $m ) = @_;
    if( $m->present_interests >= 10  or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'general_belief'};
    }
    return undef;
}

sub general_theory
{
    my( $m ) = @_;
    if( $m->present_interests >= 10  or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'general_theory'};
    }
    return undef;
}

sub general_practice
{
    my( $m ) = @_;
    if( $m->present_interests >= 10  or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'general_practice'};
    }
    return undef;
}

sub general_editor
{
    my( $m ) = @_;
    if( $m->present_interests >= 10  or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'general_editor'};
    }
    return undef;
}

sub general_helper
{
    my( $m ) = @_;
    if( $m->present_interests >= 10  or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'general_helper'};
    }
    return undef;
}

sub general_meeter
{
    my( $m ) = @_;
    if( $m->present_interests >= 10  or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'general_meeter'};
    }
    return undef;
}

sub general_bookmark
{
    my( $m ) = @_;
    if( $m->present_interests >= 10  or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'general_bookmark'};
    }
    return undef;
}

sub general_discussion
{
    my( $m ) = @_;
    if( $m->present_interests >= 10  or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'general_discussion'};
    }
    return undef;
}

sub newsmail
{
    my( $m ) = @_;
    return $m->{'newsmail'};
}

sub mailbox
{
    my( $m ) = @_;

    unless( $m->{'mailbox'} )
    {
	$m->{'mailbox'} = Para::Mailbox->new( $m );
    }
    return $m->{'mailbox'};
}

sub nicks
{
    my( $m ) = @_;

    unless( $m->{'nicks'} )
    {
	my $recs = $Para::dbix->select_list('from nick where nick_member=? order by uid', $m->id);
	my @nicks;
	foreach my $rec ( @$recs )
	{
	    push @nicks, $rec->{'uid'};
	}
	$m->{'nicks'} =  \@nicks;
    }
    return $m->{'nicks'};
}

sub add_nick
{
    my( $m, $nick, $override ) = @_;

    trim_name(\$nick);
    my $uid = name2nick($nick);
    Para::Member->validate_nick( $uid );

    my $st = "insert into nick
              ( uid, nick_member, nick_created )
              values ( ?, ?, now() )";
    my $sth = $Para::dbh->prepare( $st );
    $sth->execute($uid, $m->id);

    $m->{'nicks'} = undef;

    $m->update_topic_aliases;
    $m->update_mail_forward;
}

sub has_nick
{
    my( $m, $nick ) = @_;

    $nick = name2nick($nick);

  MYNICK: # Is $nick an nick for $m ?
  {
      foreach my $enick ( @{$m->nicks} )
      {
	  if( $nick eq $enick )
	  {
	      last MYNICK;
	  }
      }
      return 0;
  }
    return 1;
}

sub validate_nick
{
    my( $this, $nick, $override ) = @_;

    trim_name(\$nick);
    my $uid = name2nick($nick);

    if( $uid =~ /guest|admin|sysadm|root|master|skapelse|system|vaktare|guard|member|-bot|visit|temp|test|spam|skugga|ghost|serv|list|mail|bounce/ )
    {
	throw('validation', "Det här namnet är reserverat. Välj ett annat\n");
    }

    if( $uid =~ /^(ekoby|sgfb|irc|help)/ )
    {
	throw('validation', "Det här namnet är reserverat. Välj ett annat\n");
    }

    if( $uid =~ /^(mig|red|www-data|info|sales|gifts|pengar|money|shop|ekonomi|devel)$/ )
    {
	throw('validation', "Det här namnet är reserverat. Välj ett annat\n");
    }

    if( $uid =~ /^\d+$/ )
    {
	throw('validation', "Ett namn får inte bestå enbart av siffror. Välj ett annat\n");
    }

    if( $uid =~ /^\w\d+/ )
    {
	throw('validation', "Ett namn får inte bestå av en ensam bokstav följt av siffror. Välj ett annat\n");
    }

    if( length($uid) < 3 and not $override )
    {
	throw('validation', "Namnet måste vara minst 3 tecken\n");
    }

    my $topics = Para::Topic->find( $uid );
    my $person = Para::Topic->get_by_id( $C_T_PERSON );
    debug(3,"Look for existing topic");
    foreach my $t ( @$topics )
    {
	debug(3,sprintf("  Are %s a person?", $t->desig));
	if( $Para::Frame::U->level < 41 and  $t->has_rel( 1, $person ) )
	{
	    throw('validation', "Det finns en person i uppslagsverket med detta namn.\nOm detta verkligen är ditt medlemsnamn,\nhör av dig till memadmin\@paranormal.se\n");
	}
    }

    return 1;
}

sub mailaliases
{
    my( $m ) = @_;

    my $ma = $m->{'mailaliases'} ||= [];

    unless( @$ma )
    {
	#Start the list with the system email
	my $sys_email = $m->sys_email;
	push @$ma, $sys_email if $sys_email;

	# Could be empty if this is a new member
	my $recs = $Para::dbix->select_list('from mailalias where mailalias_member=? order by mailalias', $m->id);
	foreach my $rec ( @$recs )
	{
	    my $email = Para::Member::Email::Address->new( $m, $rec->{mailalias}, $rec );
	    push @$ma, $email unless $email->equals($sys_email);
	}
    }

    return wantarray ? @$ma : $ma;
}

sub set_mailaliases
{
    my( $m, $alist ) = @_;

    my $new = {};
    my $add = [];
    my $del = [];

    debug(2,"Update mailalias list");
    foreach my $row ( @$alist )
    {
	trim(\$row); next unless length($row);
	my( $addro ) = Para::Email::Address->parse( $row ) or next;
	my $addr = $addro->address;

	$new->{$addr} ++;
	debug(3,"  $addr");
    }

    # In case it's not present
    $new->{$m->sys_email} ++ if $m->sys_email;

    debug(3,"Old aliases");
    foreach my $old_alias ( $m->mailaliases )
    {
	unless( delete $new->{$old_alias->address} )
	{
	    debug(3,"  $old_alias");
	    push @$del, $old_alias->address
	}
    }
    @$add = keys %$new;

    # Del things
    debug(3,"Remove");
    foreach my $thing ( @$del )
    {
	debug(3,"  $thing");
	$m->del_mailalias( $thing );
    }

    debug(3,"Add");
    # Add things
    foreach my $thing ( @$add )
    {
	debug(3,"  $thing");
	$m->add_mailalias( $thing );
    }

    return 1;
}

sub add_mailalias
{
    my( $m, $mailalias_in ) = @_;

    my $mailalias = Para::Email::Address->parse( $mailalias_in );

    # Check if already existing
    foreach my $email ( $m->mailaliases )
    {
	return $email if $email->equals( $mailalias );
    }

    Para::Member::Email::Address->add($m, $mailalias)
	and return $m->change->success("Lade till ".$mailalias->as_string );
    return 0;
}

sub del_mailalias
{
    my( $m, $mailalias_in ) = @_;

    my $mailalias = Para::Member::Email::Address->new( $m, $mailalias_in );

#    warn "deleting mailalias ".Dumper $mailalias;

    # Check if alias in list
    return 0 unless grep {$_->equals($mailalias)} $m->mailaliases;

    $mailalias->delete and
	return $m->change->success("Tog bort $mailalias");
    return 0;
}

sub set_home_online_msn
{
    my( $m, $email ) = @_;
    return unless defined $email;
    trim(\$email);
    return if $email eq ($m->{home_online_msn}||'');
    if( length $email )
    {
	### TODO: FIXME
	my $ea = Para::Email::Address->parse( $email );
	unless( $ea->validate )
	{
	    return $m->change->fail("$email är inte en korrekt e-postadress");
	}
    }

    $m->{home_online_msn} = $email;
    $m->mark_updated;
    return $m->change->success("Ändrade home_online_msn till '$email'");
}

sub sys_email
{
    my( $m ) = @_;

    return undef unless $m->{'sys_email'};
    unless( ref $m->{'sys_email'} )
    {
	$m->{'sys_email'} =  Para::Member::Email::Address->new( $m, $m->{'sys_email'} );
    }
    return $m->{'sys_email'};
}

sub set_sys_email
{
    my( $m, $ea_str ) = @_; #ea == email_address
    die unless defined $ea_str;

    trim(\$ea_str);
    unless( length $ea_str )
    {
	return $m->change->fail("Du måste ha en e-postadress!");
    }

    my $ea = Para::Email::Address->parse( $ea_str );

    return $m->sys_email if $m->sys_email and
	$m->sys_email->equals( $ea );

    $ea->validate( $m ) or return undef;

    eval
    {
	$m->add_mailalias($ea); # Must be done before setting sys_email
	$m->{'sys_email'} = $ea;
	$m->mark_updated;
	$m->update_mail_forward;
    };
    if( $@ )
    {
	debug(0,"Error: $@");
	if( $Para::dbh->errstr and $Para::dbh->errstr =~ /duplicate key/ )
	{
	    if( $Para::dbh->errstr =~ /member_sys_email_key/ )
	    {
		throw('validation', "E-postadressen '$ea_str' är knuten till en annan medlem\n");
	    }
	    if( $Para::dbh->errstr =~ /mailalias_pkey/ )
	    {
		throw('validation', "E-postadressen '$ea_str' är knuten till en annan medlems alternativa e-postadresser\n");
	    }
	}
	die $@;
    }

    return $m->change->success("Ändrade primär e-postadress till '$ea_str'");
}

sub add_host_pattern
{
    my( $m, $pattern ) = @_;

    unless( $pattern =~ /\@/ )
    {
	$pattern = '*@'.$pattern;
    }

    unless( $Para::dbix->select_possible_record("from memberhost where memberhost_member=? and memberhost_pattern=?", $m->id, $pattern) )
    {
	my $sth_host = $Para::dbh->prepare("insert into memberhost
               ( memberhost_member, memberhost_pattern, memberhost_status, memberhost_updated )
               values ( ?, ?, 1, now() )");
	$sth_host->execute($m->id, $pattern);
    }
    return $pattern;
}

sub set_bdate_ymd_year
{
    my( $m, $year ) = @_;
    return unless defined $year;
    trim(\$year);
    return if $year eq ($m->{bdate_ymd_year}||'');
    if( length $year )
    {
	if( $year =~ /^\d\d$/ )
	{
	    $year += 1900;
	    if( $year < 1970 )
	    {
		return $m->change->fail("Ange ditt födelseår med 4 siffror");
	    }
	}
	elsif( $year !~ /^(19|20)\d\d$/ )
	{
	    return $m->change->fail("Födelseår har felaktigt format");
	}

	if( now()->year < $year + 6 )
	{
	    return $m->change->fail("Du är för ung för att vara här");
	}
    }
    $m->{'bdate_ymd_year'} = $year;
    $m->mark_updated;
    return $m->change->success("Ändrade födelseår till '$year'");
}

sub set_member_level { shift->level(@_) }
sub level
{
    my( $m, $level, $u ) = @_;
    if( defined $level )
    {
	$u ||= $Para::Frame::U;
	return $level if $level == $m->{'member_level'};

	unless( $u->level > 40 )
	{
	    throw("Nej, så får du inte göra!");
	}

	if( $level < -2 or $level > 40 )
	{
	    return $m->change->fail("Level out of range");
	}

	my $mid = $m->id;
	debug "! Member $mid level changed to $level";

	$m->{'member_level'} = $level;
	$m->mark_updated;
	$m->create_topic;

	return $m->change->success("Ändrade nivån till $level");
    }
    return $m->{'member_level'};
}

sub create_topic
{
    my( $m ) = @_;

    return if $m->topic;
    return if $m->level < 6;
    return if $m->present_contact_public < 5;

    my $t = Para::Topic->create( $m->_nickname );
    $m->{'member_topic'} =  $t->id;
    $m->mark_updated;

    $m->update_topic_aliases;
    $m->update_topic_member;
    $m->topic->mark_publish_now;

    return $t;
}

sub update_topic_member
{
    my( $m ) = @_;

    my $t = $m->topic;
    return unless $t;

    my @mglist = (406499, 396665, 396675, 396717, 396608, 396728);
    my $mg;

    my $level = $m->level;
    if( $level  >  4 ){ $mg = 406499 } # medborgare
    if( $level == 11 ){ $mg = 396665 } # lärling
    if( $level  > 11 ){ $mg = 396675 } # gesäll
    if( $level == 40 ){ $mg = 396717 } # mästare
    if( $level == 41 ){ $mg = 396608 } # livbringare
    if( $level == 42 ){ $mg = 396728 } # skapare

    $mg = 0 if $m->id == -1;

    foreach my $tid ( @mglist )
    {
	if( $tid == $mg )
	{
	    Para::Arc->create( 1,
			      $t,
			      $tid,
			      {
				  active => 1,
			      },
			      );
	}
	else
	{
	    if( my $arc = $t->arc({pred=>1, obj=>$tid}) )
	    {
		$arc->remove unless $arc->infered;
	    }
	}
    }
    
}

sub status { shift->new_status(1) }
sub new_status
{
    my( $m, $final ) = @_;
    my $level = $m->level;

    return $C_S_PROPOSED if $level < 5;
    return $C_S_PENDING if $level < 12;
    return $C_S_NORMAL if $level < 40;
    return $final ? $C_S_FINAL : $C_S_NORMAL; ### Only make final explicitly
}


sub set_gender
{
    my( $m, $gender ) = @_;

    return unless defined $gender;
    trim(\$gender);
    return if $gender eq ($m->{'gender'}||'');
    if( length $gender )
    {
	$gender = uc($gender);
	if( $gender !~ m/^[MF]?$/ )
	{
	    return $m->change->fail("Använd M/F");
	}
    }
    $m->{'gender'} = $gender;
    $m->mark_updated;
    return $m->change->success("Könsbyte genomfört utan komplikationer");
}

sub set_name_given
{
    my( $m, $fn ) = @_;
    return unless defined $fn;
    trim(\$fn);
    return if $fn eq ($m->{'name_given'}||'');
    if( length $fn )
    {
	if( $fn =~ m/\s/ )
	{
	    return $m->change->fail("Du får bara ange ett förnamn");
	}
    }
    $m->{'name_given'} = $fn;
    $m->mark_updated;
    $m->update_topic_aliases;
    if( length( $fn ) )
    {
	my $comment = "";
	if( $m->id == $Para::Frame::U->id )
	{
	    $comment = ".  Hej \U$fn";
	}
	return $m->change->success("Förnamn ändrat till $fn");
    }
    else
    {
	return $m->change->success("Förnamn raderat");
    }
}

sub set_name_family
{
    my $m = shift;
    $m->set_field('name_family', @_);
    $m->update_topic_aliases;
}

sub set_name_middle
{
    my $m = shift;
    $m->set_field('name_middle', @_);
    $m->update_topic_aliases;
}

sub set_present_contact_public
{
    my( $m, $value ) = @_;

    if( $value > $m->present_contact )
    {
	throw('validation', "Det makar ingen sense att visa mindre för medlemmar än resten av världen!!!");
    }
    $m->set_field_number('present_contact_public', $value);
    $m->topic and $m->topic->generate_url;
}

sub set_present_contact
{
    my( $m, $value ) = @_;
    $m->set_field_number('present_contact', $value);
}

sub set_home_postal_code
{
    my( $m, $zip ) = @_;
    return unless defined $zip;
    trim(\$zip);
    return if $zip eq ($m->{'home_postal_code'}||'');
    if( length $zip )
    {
	$zip =~ m/^([A-Z]{1,2}-)?([\d ]+)$/i or
	    $m->change->fail("Det där ser inte ut som ett riktigt postnummer\n".
			     "Det är okej att lämna fältet tomt");
	my $prefix = uc($1) || 'S-';
	my $number = $2 || '';
	$number =~ s/ //g;


	if( $prefix eq 'SE-' )
	{
	    $prefix = 'S-';
	}

	if( $prefix eq 'S-' )
	{
	    unless( length $number == 5 )
	    {
		return $m->change->fail("Postnummret måste ha 5 siffror");
	    }
	    if( $number =~ /^...00/ )
	    {
		return $m->change->fail("Det där ser inte ut som ett riktigt postnummer\n".
					"Det är okej att lämna fältet tomt");
	    }
	}

	$zip = $prefix . $number;
    }

    $m->{'home_postal_code'} = $zip;
    $m->mark_updated;
    $m->zip2city;

    if( my $city = $m->home_postal_city )
    {
	return $m->change->success("Postnummer ändrat. Jag gissar att du bor i $city");
    }
    elsif( not $zip )
    {
	return $m->change->success("Postnummer raderat.");
    }
    else
    {
	return $m->change->success("Postnummer ändrat. Fortsätt medan jag slår upp din ort...");
    }
}

sub phone
{
    my( $m, $publ ) = @_;

    debug(3,"Getting home_tele_phone");

    if( (not $publ and $m->present_contact >= 20) or ($publ and
        $m->present_contact_public >= 20) or $Para::Frame::U->level >= 41 or
        $m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_tele_phone'};
    }

    return undef;
}

sub phone_comment
{
    my( $m, $publ ) = @_;

    if( (not $publ and $m->present_contact >= 20) or ($publ and
        $m->present_contact_public >= 20) or $Para::Frame::U->level >= 41 or
        $m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_tele_phone_comment'};
    }

    return undef;
}

sub mobile
{
    my( $m, $publ ) = @_;

    debug(3,"Getting home_tele_mobile");

    if( (not $publ and $m->present_contact >= 20) or ($publ and
        $m->present_contact_public >= 20) or $Para::Frame::U->level >= 41 or
        $m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_tele_mobile'};
    }

    return undef;
}

sub mobile_comment
{
    my( $m, $publ ) = @_;

    if( ( not $publ and $m->present_contact >= 20) or ($publ and
	$m->present_contact_public >= 20) or $Para::Frame::U->level >= 41 or
	$m->equals( $Para::Frame::U ) )
    {
	return $m->{'home_tele_mobile_comment'};
    }

    return undef;
}

sub set_home_tele_phone
{
    my( $m, $phone ) = @_;
    return unless defined $phone;
    trim(\$phone);
    return if $phone eq ($m->{'home_tele_phone'}||'');
    if( length $phone )
    {
	$phone = $m->validate_phone( $phone ) or return undef;
    }

    $m->{'home_tele_phone'} = $phone;
    $m->mark_updated;
    return $m->change->success("Hemtelefonnummer ändrat till '$phone'");
}

sub set_home_tele_mobile
{
    my( $m, $phone ) = @_;
    return unless defined $phone;
    trim(\$phone);
    return if $phone eq ($m->{'home_tele_mobile'}||'');
    if( length $phone )
    {
	$phone = $m->validate_phone( $phone ) or return undef;
    }
    $m->{'home_tele_mobile'} = $phone;
    $m->mark_updated;
    return $m->change->success("Mobilnummer ändrat till '$phone'");
}

sub set_home_tele_fax
{
    my( $m, $phone ) = @_;
    return unless defined $phone;
    trim(\$phone);
    return if $phone eq ($m->{'home_tele_fax'}||'');
    if( length $phone )
    {
	$phone = $m->validate_phone( $phone ) or return undef;
    }
    $m->{'home_tele_fax'} = $phone;
    $m->mark_updated;
    return $m->change->success("Fax ändrat till '$phone'");
}

sub set_home_online_uri
{
    my( $m, $uri ) = @_;
    return unless defined $uri;
    trim(\$uri);
    return if $uri eq ($m->{'home_online_uri'}||'');
    if( length $uri )
    {
	$uri = $m->validate_uri( $uri ) or return undef;
    }
    $m->{'home_online_uri'} = $uri;
    $m->mark_updated;
    return $m->change->success("Webbplats ändrad till '$uri'");
}


sub username { shift->{'nickname'} }  # Used by Para::Frame::User
sub _nickname { shift->{'nickname'} } # Internal method
sub nickname
{
    my( $m, $publ ) = @_;
    # Set publ true if this will be given to the public

    if( (not $publ and $m->present_contact >= 2) or ($publ and
	    $m->present_contact_public >= 2) or $Para::Frame::U->level >= 41 or
	    $m->equals( $Para::Frame::U ) )
    {
	return $m->{'nickname'};
    }
    else
    {
	return undef;
    }
}

sub nickname_trimmed
{
    return name2nick( $_[0]->{'nickname'} );
}

sub set_nickname
{
    my( $m, $nickname ) = @_;
    return unless defined $nickname;

    trim_name(\$nickname);
    return if $nickname eq ($m->_nickname||'');

    # NOT NULL
    length $nickname or
	return $m->change->fail("Du måste ha ett namn\n");

    my $uid = name2nick($nickname);

    # TODO: use $m->has_nick($uid)

  TEST:
    {
	foreach my $nick ( @{$m->nicks} )
	{
	    last TEST if $nick eq $uid;
	}

	if( $Para::Frame::U->level > 40 )
	{
	    $m->add_nick( $uid, 1 );
	}
	else
	{
	    return $m->change->fail("Namnet '$nickname' liknar inte något av dina alias\n");
	}
    }

    if( $nickname eq $m->_nickname )
    {
	return 1; # No change
    }


    # TODO: chatnick for every nick
    my $chat_nick = name2chat_nick($nickname);

    $m->{'nickname'} = $nickname;
    $m->{'chat_nick'} = $chat_nick;
    $m->mark_updated;
    $m->update_topic_aliases;
    return $m->change->success( "Ändrade alias till $nickname\n" );
}

sub chatnick
{
    my( $m ) = @_;

    return $m->{'chat_nick'};
}

sub chat_level
{
    my( $m ) = @_;

    ## See C_C_... in Constants
    return $m->{'chat_level'};
}

sub latest_in
{
    my( $m, $time ) = @_;

    if( $time )
    {
	$m->{'latest_in'} = Para::Frame::Time->get( $time );
	$m->score_change('logged_in', 1);
	$m->mark_unsaved;
	$ONLINE_COUNT ++;
    }

    my $latest_in = $m->{'latest_in'};
    if( not $latest_in and $m->equals($Para::Frame::U) )
    {
	return $m->{'latest_in'} = now();
    }

    unless( ref $m->{'latest_in'} )
    {
	return $m->{'latest_in'} = date( $latest_in );
    }

    return $m->{'latest_in'};
}

sub latest_out
{
    my( $m, $time ) = @_;

    if( $time )
    {
	$m->{'latest_out'} = Para::Frame::Time->get( $time );

	# Update time_online
	my $delta = ( $time->epoch - $m->latest_in()->epoch );
	$m->score_change('time_online', $delta);

	$m->mark_unsaved;
	$ONLINE_COUNT --;
	return $m->{'latest_out'};
    }

    unless( ref $m->{'latest_out'} )
    {
	return $m->{'latest_out'} = date( $m->{'latest_out'} );
    }

    return $m->{'latest_out'};
}

sub latest_seen
{
    my( $m, $time ) = @_;

    if( $time )
    {
	$time = Para::Frame::Time->get( $time );
	$m->{'latest_seen'} = $time;

	# Update DBM
	my $db = paraframe_dbm_open( $C_DB_ONLINE );
	$db->{ $m->id } = $time->epoch;
    }
    else
    {
	$m->{'latest_seen'} ||= $m->latest_in;

	# Update info if seen more than 15 mins ago
	if( not $m->{'latest_seen'} or
	    ( now()->epoch - $m->{'latest_seen'}->epoch > 60 * 15 ) )
	{
	    my $db = paraframe_dbm_open( $C_DB_ONLINE );
	    if( my $last = $db->{ $m->id } )
	    {
		$m->{'latest_seen'} = date( $last );
	    }
	}
    }

    return $m->{'latest_seen'};
}

sub online
{
    if( $_[0]->latest_in )
    {
	if( $_[0]->latest_in >= $_[0]->latest_out )
	{
	    return 1;
	}
    }

    return 0;
}

sub offline
{
    return not $_[0]->online;
}

sub created
{
    unless( ref $_[0]->{'member_created'} )
    {
	return $_[0]->{'member_created'} =
	    date( $_[0]->{'member_created'} );
    }
    return $_[0]->{'member_created'};
}

sub updated
{
    unless( ref $_[0]->{'member_updated'} )
    {
	return $_[0]->{'member_updated'} =
	    date( $_[0]->{'member_updated'} );
    }
    return $_[0]->{'member_updated'};
}

sub interests_updated
{
    unless( ref $_[0]->{'intrest_updated'} )
    {
	return $_[0]->{'intrest_updated'} =
	    date( $_[0]->{'intrest_updated'} );
    }
    return $_[0]->{'intrest_updated'};
}

sub payment_expire
{
    unless( ref $_[0]->{'member_payment_period_expire'} )
    {
	return $_[0]->{'member_payment_period_expire'} =
	    date( $_[0]->{'member_payment_period_expire'} );
    }
    return $_[0]->{'member_payment_period_expire'};
}

sub payment_active
{
    my( $m ) = @_;
    my $expire = $m->payment_expire or return 0;
    return 0 if now() > $expire;
    return 1;
}

sub payment_period_length
{
    my( $m ) = @_;
    return $m->{'member_payment_period_length'};
}

sub payment_period_cost
{
    my( $m ) = @_;
    return $m->{'member_payment_period_cost'};
}

sub payment_level
{
    my( $m ) = @_;
    return $m->{'member_payment_level'};
}

sub payment_total
{
    my( $m ) = @_;
    return $m->{'member_payment_total'};
}

sub payment_rate
{
    my( $m ) = @_;
    return undef unless $m->{'member_payment_period_length'};
    return sprintf('%.2f', $m->{'member_payment_period_cost'} * (ONE_MONTH/ONE_DAY) / $m->{'member_payment_period_length'} );
}

sub payment_total_rate
{
    my( $m ) = @_;
    my $months = now()->delta_md( $m->created )->delta_months;
    return undef unless $months;
    return sprintf('%.2f', $m->{'member_payment_total'} / $months );
}

sub payments
{
    my( $m ) = @_;

#    warn "in payments";
    if( $Para::Frame::U->level >= 41 or $m->equals( $Para::Frame::U ) or
	$m->present_gifts >= 30  )
    {
	my $recs = $Para::dbix->select_list('from payment where payment_member=? and payment_completed is true order by payment_date', $m->id);
#	warn Dumper $recs;
	my @payments = map Para::Payment->new($_), @$recs;
	return wantarray ? @payments : \@payments;
    }

    throw('denied', "Hemliga uppgifter");
}

sub update_mail_forward
{
    my( $m ) = @_;

    ### NB! changes are made even if the action results in a rollback

    debug(3,sprintf("Update_mail_forward for %s", $m->nickname));

    my $mid = $m->id;
    my $address = $m->sys_email;
    my $sys_uid = $m->sys_uid || '';
    my $nicks = $m->nicks;

    # TODO: Do not forward to our domains

    # Special handling for local e-mail
    #
    if( $address =~ /^(.*?)\@paranormal\.se$/ )
    {
	$address = $1;

	$sys_uid or return $m->change->fail("Du har inte en postlåda här\n");

	unless( $m->has_nick( $address ) )
	{
	    return $m->change->fail("Du kan inte skicka posten ".
				    "till någon annan\n");
	}

	$address = $sys_uid; # Send to actual mailbox, not an alias
    }

    # Forward mail if citizen or having a mailbox
    if( $m->level >= 5 or $m->sys_uid )
    {
	foreach my $nick ( @{$nicks} )
	{
	    $m->set_dbm_alias( $nick, $address );
	}
    }
    else
    {
	foreach my $nick ( @{$nicks} )
	{
	    $m->unset_dbm_alias( $nick );
	}
    }

    return 1;
}

sub update_topic_aliases
{
    my( $m ) = @_;

    my $t = $m->topic;
    return 0 unless $t;

    my %al;

    my $ng = trim_name( $m->name_given  );
    my @nm = split /\s/, trim_name( $m->name_middle );
    my $nf = trim_name( $m->name_family );
    my $ngi = substr trim_name( $m->name_given  ),0,1;
    my @nmi = map substr($_, 0, 1), @nm;
    my $nfi = substr trim_name( $m->name_family ),0,1;

    if( $ng and $nf )
    {
	$al{ lc trim_name("$ng $nf") }               = [1,0];
	$al{ lc trim_name("$ng @nm $nf") }           = [1,1];
	$al{ lc trim_name("$ngi $nfi") }             = [0,0];
	$al{ lc trim_name("$ngi$nfi") }              = [0,0];
	$al{ lc trim_name($ngi.join('',@nmi).$nfi) } = [0,0];
	$al{ lc trim_name("$ngi @nmi $nfi") }        = [0,0];
	$al{ lc trim_name("$ng $nfi") }              = [0,0];
	$al{ lc trim_name("$ng @nmi $nfi") }         = [0,0];

	$al{ lc trim_name("$ngi $nf") }              = [0,0];
	$al{ lc trim_name("$ngi @nmi $nf") }         = [0,0];
	$al{ lc trim_name("$nf, $ng") }              = [1,0];
	$al{ lc trim_name("$nf, $ng @nmi") }         = [1,0];
	$al{ lc trim_name("$nf, $ng @nm") }          = [1,1];
	$al{ lc trim_name("$nf, $ngi") }             = [0,0];
	$al{ lc trim_name("$nf, $ngi @nmi") }        = [1,0];
    }
    if( $ng )
    {
	$al{ lc trim_name("$ng") }        = [0,0];
    }
    if( $nf )
    {
	$al{ lc trim_name("$nf") }        = [0,0];
    }

    foreach my $nick (@{ $m->nicks })
    {
	$al{lc $nick}                     = [0,1];
    }

    $al{lc $m->_nickname}                 = [0,1];
    $al{lc $m->chatnick}                  = [0,1];

    foreach my $alias ( keys %al )
    {
	next unless length $alias;
	unless( $t->has_alias( $alias ) )
	{
	    $t->add_alias( $alias,
			   {
			       'autolink' => $al{$alias}[0],
			       'index' => $al{$alias}[1],
			   }
			   );
	}
	
    }
}

sub dbm_alias
{
    my( $m, $nick ) = @_;

    $m->has_nick( $nick ) or
      throw( 'denied', sprintf "%s doesn't have the nick '%s'\n",
	$m->_nickname, $nick );

    my $db = paraframe_dbm_open( $C_DB_ALIAS );
    return $db->{ $nick };
}

sub set_dbm_alias
{
    my( $m, $nick, $address ) = @_;

    $address ||= $m->sys_uid || $m->sys_email;
    $nick or throw( 'incomplete', "nick param missing" );

    my $db = paraframe_dbm_open( $C_DB_ALIAS );
    debug(3,"Setting $nick forward to $address");
    return $db->{ $nick } = $address;
}

sub unset_dbm_alias
{
    my( $m, $nick ) = @_;

    $nick or throw( 'incomplete', "nick param missing" );

    my $db = paraframe_dbm_open( $C_DB_ALIAS );
    debug(3,"Removing $nick forward");
    return delete $db->{ $nick };
}

sub set_dbm_passwd
{
    my( $m ) = @_;

    my $passwd = $m->{'passwd'};
    my $sys_uid = $m->sys_uid;
    return unless $sys_uid;

    my $db = paraframe_dbm_open( $C_DB_PASSWD );

    return $db->{ $sys_uid } = $passwd;
}

sub unset_dbm_passwd
{
    my( $m ) = @_;

    my $sys_uid = $m->sys_uid;
    my $db = paraframe_dbm_open( $C_DB_PASSWD );

    return delete $db->{ $sys_uid } ? 1 : 0;
}

sub dbm_passwd_check
{
    my( $m ) = @_;

    my $db = paraframe_dbm_open( $C_DB_PASSWD );
    my $dbm_passwd = $db->{ $m->sys_uid };

    if( $dbm_passwd eq $m->{'passwd'} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub dbm_passwd_exist
{
    my( $m ) = @_;

    return 0 unless $m->sys_uid;
    my $db = paraframe_dbm_open( $C_DB_PASSWD );
    my $dbm_passwd = $db->{ $m->sys_uid };
    return length $dbm_passwd ? 1 : 0;
}

sub validate_phone
{
    my( $m, $phone ) = @_;

    my $orig_phone = $phone;
    $phone =~ s/\s*-\s*/-/g;
    $phone =~ s/\s+/ /g;
    $phone =~ s/\(\)//g;

    my( $country, $number ) = $phone =~
      m/^(\+\d{1,3} )?0?([\d\- ]+)$/
	or return $m->change->fail("'$orig_phone' är inte en korrekt telefonnummer\n");
    unless( $country )
    {
	$country = '+46 ';
	$m->change->note("Jag antar att '$phone' är ett svenskt telefonnummer");
    }
    return $country . $number;
}

sub validate_uri
{
    my( $m, $url ) = @_;

    my( $prot, $host, $port, $path ) = $url =~
      m/^(?:(https?:)\/\/)?([\w\-\.]+)(:\d+)?(\/\S+)?/
	or return $m->change->fail("URL '$url' har ett felaktigt format");
    unless( $host =~ /\.\w{2,4}$/ )
    {
	return $m->change->fail("URL '$url' har ett felaktigt format");
    }
    $prot ||= 'http:';
    $port ||= '';
    $path ||= '/';
    return "$prot//$host$port$path";
}

sub mark_unsaved
{
    my( $m ) = @_;

    my $mid = $m->id;

    $UNSAVED{$mid} = $m;
}

sub mark_updated
{
    my( $m, $time ) = @_;
    $time ||= now();
    $m->{'member_updated'} = $time;
    $m->mark_unsaved;
    return $time;
}

sub commit
{
    eval
    {
	foreach my $m ( values %UNSAVED )
	{
	    $m->save;
	}
    };
    if( $@ )
    {
	debug $@;
	rollback();
    }
}

sub rollback
{
    foreach my $m ( values %UNSAVED )
    {
	$m->discard_changes;
    }
    %UNSAVED = ();
}

sub save
{
    my( $m ) = @_;

    my $mid = $m->id;

    my( @fields, @values );

    debug(1,"Saving member $mid");
    my $saved = $m->get_by_id( $mid, undef, 1); # Nocache

    my $types =
    {
	sys_uid                      => 'string',
	sys_email                    => 'email',
	sys_logging                  => 'integer',
	sys_level                    => 'integer',
	present_intrests             => 'integer',
	present_activity             => 'integer',
	present_gifts                => 'integer',
	general_belief               => 'integer',
	general_theory               => 'integer',
	general_practice             => 'integer',
	general_editor               => 'integer',
	general_helper               => 'integer',
	general_meeter               => 'integer',
	general_bookmark             => 'integer',
	general_discussion           => 'integer',
	bdate_ymd_year               => 'integer',
	member_level                 => 'integer',
	member_topic                 => 'integer',
	gender                       => 'string',
	nickname                     => 'string',
	name_prefix                  => 'string',
	name_given                   => 'string',
	name_suffix                  => 'string',
	home_postal_name             => 'string',
	home_postal_street           => 'string',
	home_postal_visiting         => 'string',
	home_postal_code             => 'string',
	home_postal_city             => 'string',
	home_tele_phone              => 'string',
	home_tele_phone_comment      => 'string',
	home_tele_mobile             => 'string',
	home_tele_mobile_comment     => 'string',
	home_tele_fax                => 'string',
	home_tele_fax_comment        => 'string',
	home_online_msn              => 'email',
	home_online_icq              => 'integer',
	home_online_skype            => 'string',
	home_online_aol              => 'integer',
	home_online_uri              => 'string',
	home_online_email            => 'email',
	chat_nick                    => 'string',
	geo_x                        => 'float',
	geo_y                        => 'float',
	geo_precision                => 'integer',
	latest_in                    => 'date',
	latest_out                   => 'date',
	member_payment_period_length => 'integer',
	member_payment_period_expire => 'date',
	member_payment_period_cost   => 'integer',
	member_payment_total         => 'integer',
	statement                    => 'string',
	show_style                   => 'string',
	show_complexity              => 'integer',
	show_detail                  => 'integer',
	show_edit                    => 'integer',
	show_level                   => 'integer',
	newsmail                     => 'integer',
	presentation                 => 'string',
	member_comment_admin         => 'string',
	member_topic                 => 'integer',
	chat_level                   => 'integer',
    };

    my $changes = $Para::dbix->save_record({
	rec_new => $m,
	rec_old => $saved,
	table   => 'member',
	types   => $types,
	keyval  => $mid,
	fields_to_check => [keys %$types],
    });


    # Also save scores
    #
    $changes += $m->save_scores({
	m_old => $saved,
    });


    delete $UNSAVED{$mid};

    return $changes; # The number of changes
}

sub save_scores
{
    my( $m, $params ) = @_;

    $params ||= {};
    my $mid = $m->id;

    my $m_old = $params->{'m_old'} ||
	$m->get_by_id( $mid, undef, 1);

    my $m_scores = $m->score_hash;
    my $m_old_scores = $m_old->score_hash;

    return $Para::dbix->save_record({
	rec_new => $m_scores,
	rec_old => $m_old_scores,
	table   => 'score',
	key     => 'score_member',
	keyval  => $mid,
    });
}

sub discard_changes  # Member changed. Refresh from DB
{
    my( $m ) = @_;

    my $mid = $m->id;

    debug(1,"discard changes for member $mid");

    my $saved = $m->get_by_id( $mid, undef, 1); # no cache

    if( not $saved )
    {
	return undef;
    }

    ###  Replace all parts of object
    #
    foreach my $key ( keys %$m )
    {
	delete $m->{$key};
    }
    foreach my $key ( keys %$saved )
    {
	$m->{$key} = $saved->{$key};
    }

    return $m;
}

sub change { $Para::Frame::REQ->change }
sub changes { $Para::Frame::REQ->change }

sub zip2city
{
    my( $m ) = @_;

    my $zip = $m->home_postal_code;

    if( $zip and $zip =~ s/^S-// )
    {
	debug(3,"Fixing zip $zip");

	my $sth = $Para::dbh->prepare(
	      "select * from zip, city where zip_city=city and zip=?") or die;
	$sth->execute($zip) or die;
	my $rec = $sth->fetchrow_hashref;
	$sth->finish;

	if( my $city_name = $rec->{'city_name'} )
	{
	    $city_name = undef if $zip eq '';
	    debug(3,"  Found city $city_name");
	    $m->{'home_postal_city'} = $city_name;
	}
	else
	{
	    debug(3,"Removing city");
	    $m->{'home_postal_city'} = undef;
	}

	if( my $x = $rec->{'zip_x'} || $rec->{'city_x'} )
	{
	    my $y = $rec->{'zip_y'} || $rec->{'city_y'};

	    debug(3,"  Got koordinates $x:$y");
	    my $precision = $rec->{'zip_precision'} || $rec->{'city_precision'};

	    $m->{'geo_x'} = $x;
	    $m->{'geo_y'} = $y;
	    $m->{'geo_precision'} = $precision || 0;
	}
	else
	{
	    debug(3,"Removing koordinates");

	    $m->{'geo_x'} = undef;
	    $m->{'geo_y'} = undef;

	    # Set geo precision to undef so that it will trigger a coord loading
	    $m->{'geo_precision'} = undef;
	}
    }
    else
    {
	debug(3,"Removing koordinates and city");

	$m->{'home_postal_city'} = undef;
	$m->{'geo_x'} = undef;
	$m->{'geo_y'} = undef;
	$m->{'geo_precision'} = 0;
    }

    $m->mark_updated;
}

sub score_change
{
    my( $m, $field, $delta ) = @_;

    my $mid = $m->id;
    $delta ||= 1;

    my $value = $m->score($field) + $delta;

    $m->mark_unsaved;
    return $m->{'score'}{$field} = $value;
}

sub score
{
    my( $m, $field ) = @_;

    $m->{'score'} ||= $m->score_hash;
    return $m->{'score'}{$field};
}

sub score_hash
{
    my( $m ) = @_;

    unless( $m->{'score'} )
    {
	my $rec = $Para::dbix->select_record("from score where score_member=?", $m->id);
	$m->{'score'} = $rec;
    }

    return $m->{'score'};
}

sub total_time_online
{
    # TODO: Convert to DateTime::Duration

    my( $m ) = @_;
    if( $m->equals( $Para::Frame::U ) )
    {
	return Time::Seconds->new( time - $m->latest_in->epoch + $m->score('time_online') );
    }
    else
    {
	return $m->score('time_online');
    }
}

sub visits
{
    return shift->score('logged_in');
}

sub mark_publish
{
    my( $m ) = @_;

    if( my $t = $m->topic )
    {
	$t->mark_publish;
    }
}

sub publish
{
    my( $m ) = @_;

    if( my $t = $m->topic )
    {
	$t->publish;
    }
}

sub vacuum
{
    my( $m ) = @_;

    # Clear out the cache
    $m->discard_changes;

    # Fix mailbox data
    $m->update_mail_forward;
    $m->set_dbm_passwd;

    if( $m->sys_uid )
    {
	unless( $m->mailbox->exist )
	{
	    $m->mailbox->create;
	}
    }

    $m->create_topic;

    if( $m->topic )
    {
	$m->update_topic_aliases;
	$m->update_topic_member;
	$m->topic->vacuum;
	$m->topic->mark_publish_now;
    }

    $m->reset_payment_stats;
}

sub reset_payment_stats
{
    my( $m ) = @_;

    debug(0,"Resetting payment stats");

    my $period_length = 30;
    my $expire = $m->created + duration( weeks => 1 );

    $m->{'member_payment_period_length'} = 30;
    $m->{'member_payment_period_expire'} = $expire;
    $m->{'member_payment_period_cost'}   = 0;
    $m->{'member_payment_total'}         = 0;

    foreach my $p ( $m->payments )
    {
	debug(0,sprintf("  Readd payment %d", $p->id));
	$p->add_to_member_stats;
    }

    $m->mark_unsaved;
}


sub remove
{
    my( $m, $reason ) = @_;

    my $mid = $m->id;
    my $u = $Para::Frame::U;

    if( $m->id != $u->id and $u->level < 41 )
    {
	throw('denied', "Du har inte access för att ta bort någon");
    }

    if( $mid < 2 )
    {
	throw('denied', "Den här meta-medlemmen kan inte raderas");
    }

    if($m->payment_total)
    {
	throw('denied', "Den här medlemen är kopplad till bokföringen");
    }

    debug "! Removing member $mid from database";


    # Don't bother about failed email
    # Send before we remove info about reciepient
    Para::Email->send_by_proxy({
	    subject => "Medlemskap raderat",
	    m => $m,
	    template => 'member_remove.tt',
	});


    # Remove from nickname cache
    foreach my $nick (@{ $m->nicks })
    {
	delete $Para::Member::CACHE->{$nick};
    }


    if( my $t = $m->topic )
    {
	$t->delete_cascade;
    }

    $m->mailbox->remove;

    $Para::dbh->do("delete from nick where nick_member = ?", undef, $mid);
    $Para::dbh->do("delete from passwd where passwd_member = ?", undef, $mid);
    $Para::dbh->do("delete from member where member = ?", undef, $mid);
    $Para::dbh->do("delete from mailalias where mailalias_member = ?", undef, $mid);
    $Para::dbh->do("delete from memberhost where memberhost_member = ?", undef, $mid);
    $Para::dbh->do("delete from intrest where intrest_member = ?", undef, $mid);
    $Para::dbh->do("delete from score where score_member = ?", undef, $mid);
    $Para::dbh->do("update t set t_changedby=-2 where t_changedby = ?", undef, $mid);
    $Para::dbh->do("update t set t_createdby=-2 where t_createdby = ?", undef, $mid);
    $Para::dbh->do("update rel set rel_changedby=-2 where rel_changedby = ?", undef, $mid);
    $Para::dbh->do("update rel set rel_createdby=-2 where rel_createdby = ?", undef, $mid);
    $Para::dbh->do("update publ set publ_changedby=-2 where publ_changedby = ?", undef, $mid);
    $Para::dbh->do("update publ set publ_createdby=-2 where publ_createdby = ?", undef, $mid);
    $Para::dbh->do("update ts set ts_changedby=-2 where ts_changedby = ?", undef, $mid);
    $Para::dbh->do("update ts set ts_createdby=-2 where ts_createdby = ?", undef, $mid);
    $Para::dbh->do("update reltype set reltype_changedby=-2 where reltype_changedby = ?", undef, $mid);
    $Para::dbh->do("update talias set talias_changedby=-2 where talias_changedby = ?", undef, $mid);
    $Para::dbh->do("update talias set talias_createdby=-2 where talias_createdby = ?", undef, $mid);
    $Para::dbh->do("update ipfilter set ipfilter_changedby=-2 where ipfilter_changedby = ?", undef, $mid);
    $Para::dbh->do("update ipfilter set ipfilter_createdby=-2 where ipfilter_createdby = ?", undef, $mid);


    # Remove from mid cache
    #
    delete $Para::Member::CACHE->{$mid};


    # Sync with u
    #
    if( $mid == $u->id )
    {
	$u->logout;
    }


    # Give room for something else
    $Para::Frame::REQ->yield;

    return 1;
}

sub clear_cached
{
    my( $m ) = @_;

    $m->{interests} = undef;
    $m->{nicks} = undef;
    $m->{mailaliases} = undef;
    $m->{score} = undef;
}


#################################################################

sub by_name  ## LIST CONSTRUCTOR
{
    my( $class, $identity, $complete, $censor ) = @_;

    my %recs;

    trim( \$identity );

    length($identity) or confess "Identity param missing";


    $identity = lc( $identity );
    my $nick = name2nick( $identity );

    my $found = 0;

    if( $identity eq 'mig' )
    {
	$identity = $Para::Frame::U->id;
    }

    my $censor_part = "";
    if( $censor and $Para::Frame::U->level < 41)
    {
	$censor_part .= " and present_contact > 1";
	$censor_part .= " and member_level > 0";
    }


    if( $identity =~ m/\@/ )
    {
	my $recs2 = $Para::dbix->select_list("from member, mailalias where
                          mailalias_member=member and
                          lower(mailalias) = lower(?) $censor_part",
			       $identity);

	my $recs3 =  $Para::dbix->select_list("from member where
                          lower(home_online_msn) = lower(?) $censor_part",
			       $identity);

	foreach my $rec ( @$recs2, @$recs3 )
	{
	    next unless $rec;
	    my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	    next if $censor_part and $m->present_contact < 5;
	    $recs{$rec->{'member'}} = $m;
	    $found ++;
	}
    }
    elsif( $identity =~ m/^\d+$/ )
    {
	if( my $rec = $Para::dbix->select_possible_record("from member where member=? $censor_part", $identity) )
	{
	    my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	    unless( $censor_part and $m->present_contact < 5 )
	    {
		$recs{$rec->{'member'}} = $m;
		$found ++;
	    }
	}
	elsif( my $recs = $Para::dbix->select_list("from member where home_online_icq=? $censor_part", $identity) )
	{
	    foreach my $rec ( @$recs )
	    {
		my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
		next if $censor_part and $m->present_contact < 5;
		$recs{$rec->{'member'}} = $m;
		$found ++;
	    }
	}
	else
	{
	    debug(0,"Ingen medlem har medlemsnumret $identity");
#	    die ['notfound', "Ingen medlem har medlemsnumret $identity\n"];
	    throw('notfound', "Ingen medlem har medlemsnumret eller ICQ $identity\n");
	}
    }
    else
    {
	if( my $rec = $Para::dbix->select_possible_record("from member, nick where nick_member=member
                                              and uid=? $censor_part", $nick) )
	{
	    my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	    unless( $censor_part and $m->present_contact < 5 and lc($nick) ne lc($m->nickname) )
	    {
		$recs{$rec->{'member'}} = $m;
		$found ++;
	    }
	}

	if( $complete or not $found )
	{
	    my( @names ) = split /\s+/, $identity;
	    my @parts;
	    my @data;

	    foreach my $name ( @names )
	    {
		push @parts, "(lower(name_given)=? or lower(name_middle)=? or lower(name_family)=?)";
		push @data, $name, $name, $name;
	    }
	    my $part = join " and ", @parts;
#	    warn "select * from member where $part (@data)\n";
	    my $recs2 = $Para::dbix->select_list("from member where $part $censor_part", @data);
	    foreach my $rec ( @$recs2 )
	    {
		my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
		next if $censor_part and $m->present_contact < 12;
		$recs{$rec->{'member'}} = $m;
		$found++;
	    }
	}

	if( $complete or not $found )
	{
	    my $recs2 = $Para::dbix->select_list("from member where lower(home_online_email) like ? $censor_part", "$identity%");
	    foreach my $rec ( @$recs2 )
	    {
		next unless $rec->{'home_online_email'} =~ /^${identity}[^a-zA-Z]/;
		my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
		next if $censor_part and $m->present_contact < 5;
		$recs{$rec->{'member'}} = $m;
		$found ++;
	    }
	}

	if( $complete or not $found )
	{
	    my $recs2 = $Para::dbix->select_list("from member, mailalias where mailalias_member=member and lower(mailalias) like ? $censor_part",
                                    "$identity%");
	    foreach my $rec ( @$recs2 )
	    {
		next unless $rec->{'mailalias'} =~ /^${identity}[^a-zA-Z]/;
		my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
		next if $censor_part and $m->present_contact < 12;
		$recs{$rec->{'member'}} = $m;
		$found ++;
	    }
	}

	if( $complete or not $found )
	{
	    my $recs2 = $Para::dbix->select_list("from member where lower(home_online_msn) like ? $censor_part", "$identity%");
	    foreach my $rec ( @$recs2 )
	    {
		next unless $rec->{'home_online_msn'} =~ /^${identity}[^a-zA-Z]/;
		my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
		next if $censor_part and $m->present_contact < 5;
		$recs{$rec->{'member'}} = $m;
		$found ++;
	    }
	}

    }

    my @sorted = sort { lc($a->{'nickname'}) cmp lc($b->{'nickname'}) } values %recs;

    return \@sorted;
}

#################################################################



sub search
{
    my( $this, $crits ) = @_;

    $crits ||= {};
    my $all = 0;
    $all = 1 if $crits->{'all'};

    my $req = $Para::Frame::REQ;
    my $q = $req->q;

    my $belief     = $q->param('_belief')||0;
    my $knowledge  = $q->param('_knowledge');
    my $theory     = $q->param('_theory');
    my $skill      = $q->param('_skill');
    my $practice   = $q->param('_practice');
    my $bookmark   = $q->param('_bookmark');
    my $editor     = $q->param('_editor');
    my $discussion = $q->param('_discussion');
    my $meeter     = $q->param('_meeter');
    my $experience = $q->param('_experience');
    my $helper     = $q->param('_helper');
    my $newsmail   = $q->param('_newsmail') || 3;
    my $union      = $q->param('union');
    my $dist       = $q->param('dist');
    my $place      = $q->param('place') || 'mig';
    my $sex_m      = $q->param('_sex_m') || 0;
    my $sex_f      = $q->param('_sex_f') || 0;
    my $age_min    = $q->param('_age_min');
    my $age_max    = $q->param('_age_max');
    my $level_min  = $q->param('_level_min');
    my $level_max  = $q->param('_level_max');
    my $has_uri    = $q->param('_uri');
    my $has_icq    = $q->param('_icq');
    my $has_phone  = $q->param('_phone');
    my $presentation  = $q->param('_presentation');
    my $order      = $q->param('order') || 'dist';

    my $interest_words = Para::Frame::Widget::rowlist('interest');
    my( $interest_part,  @where_data, @where_part, @select );

    debug 3, "Interest words: @$interest_words";

    if( $sex_m and $sex_f )
    {
	$sex_m = 0;
	$sex_f = 0;
    }

    if( @$interest_words )
    {
	my( @interest, @interest_part );
	foreach my $word ( @$interest_words )
	{
	    warn "Add $word to spec\n";

	    my $topic;
	    eval
	    {
		$topic = Para::Topic->find_one( $word );
	    };
	    if( $@ )
	    {
		if( ref $@ and $@->[0] eq 'alternatives' )
		{
		    my $res = $req->result;
		    my $alt = $res->{'info'}{'alternatives'} ||= {};

		    my $block;
		    foreach my $oldword ( @$interest_words )
		    {
			if( $word ne $oldword )
			{
			    $block .= $oldword."\n";
			}
		    }

		    $alt->{'rowformat'} = sub
		    {
			my( $t ) = @_;
			
			my $tid = $t->id;
			my $ver = $t->ver;

			my $val = $block . $tid ." ".$t->desig;

			my $replace = $alt->{'replace'} || 'interest';
			my $view = $alt->{'view'} || $req->template_uri;
			
			return sprintf( "<td>%s <td>%d v%d <td>%s <td>%s",
					&Para::Frame::Widget::jump('välj',
					     $view,
					     {
						 step_replace_params => $replace,
						 $replace => $val,
						 run => 'next_step',
						 class => 'link_button',
					     }),
					$t->id,
					$ver,
					$t->link,
					$t->type_list_string,
					);
		    };
		}
		die $@; # Propagate error
	    }

	    my $part =
	    {
		id => $topic->id,
		interest => "intrest > 30",
	    };
	    push @interest, $part;

	    $part->{belief} = "belief > 30" if $belief > 0;
	    $part->{belief} = "belief < -30" if $belief < 0;
	    $part->{experience} = "experience > 20" if $experience;
	    $part->{bookmark} = "bookmark > 50" if $bookmark;
	    $part->{knowledge} = "knowledge > 40" if $knowledge;
	    $part->{theory} = "theory > 60" if $theory;
	    $part->{skill} = "skill > 30" if $skill;
	    $part->{practice} = "practice > 60" if $practice;
	    $part->{editor} = "editor > 30" if $editor;
	    $part->{helper} = "helper > 30" if $helper;
	    $part->{meeter} = "meeter > 50" if $meeter;
	}

	foreach my $interest ( @interest )
	{
	    my $cond = "";
	    foreach my $key ( keys %$interest )
	    {
		next if $key eq 'id';
		$cond .= "and $interest->{$key} ";
	    }

	    push @interest_part, "member in (select intrest_member ".
	      "from intrest where intrest_topic=? $cond)";
	    push @where_data,  $interest->{'id'};
	}

	if( $union )
	{
	    $interest_part = join " or ", @interest_part;
	    push @where_part, "( $interest_part )" if  $interest_part;
	}
	else
	{
	    $interest_part = join " and ", @interest_part;
	    push @where_part, $interest_part if  $interest_part;
	}
    }
    else
    {
#	throw('validation', "Ha med åtminstonne ett intresse\n");

	my $part =
	{
	    member => "member > 0",
	};

	$part->{belief} = "general_belief > 30" if $belief > 0;
	$part->{belief} = "general_belief < -30" if $belief < 0;
	$part->{bookmark} = "general_bookmark > 50" if $bookmark;
	$part->{theory} = "general_theory > 60" if $theory;
	$part->{practice} = "general_practice > 60" if $practice;
	$part->{editor} = "general_editor > 30" if $editor;
	$part->{helper} = "general_helper > 30" if $helper;
	$part->{meeter} = "general_meeter > 50" if $meeter;

	foreach my $key ( keys %$part )
	{
	    push @where_part, $part->{$key};
	}

	foreach my $key (qw(experience knowledge skill))
	{
	    if( $part->{$key} )
	    {
		throw('validation', "Du kan bara söka på $skill i kombination med ett urval av intressen\n");
	    }
	}
    }

    push @where_part, "general_discussion>40" if $discussion;

    if( $newsmail )
    {
	debug 3, "newsmail: $newsmail";
	push @where_part, "newsmail >= ?";
	push @where_data,  $newsmail;
    }

    if( $sex_m )
    {
	push @where_part, "gender = 'M'";
    }

    if( $sex_f )
    {
	push @where_part, "gender = 'F'";
    }

    if( $age_min )
    {
	push @where_part, "bdate_ymd_year <= ?";
 	push @where_data,  now()->year - $age_min;
    }

    if( $age_max )
    {
	push @where_part, "bdate_ymd_year >= ?";
 	push @where_data,  now()->year - $age_max;
    }

    if( $level_min )
    {
	push @where_part, "member_level >= ?";
 	push @where_data,  $level_min;
    }

    if( $level_max )
    {
	push @where_part, "member_level <= ?";
 	push @where_data,  $level_max;
    }

    if( $has_uri )
    {
	push @where_part, "home_online_uri is not null";
    }

    if( $has_icq )
    {
	push @where_part, "home_online_icq is not null";
    }

    if( $has_phone )
    {
	push @where_part, "( home_tele_phone is not null or home_tele_mobile is not null )";
    }

    if( $presentation )
    {
	push @where_part, "present_contact >= 10 and lower(presentation) like lower(?)";
	$presentation =~ s/%//g;
	push @where_data,  "%$presentation%";
    }


    if( $Para::Frame::U->level < 41 )
    {
	push @where_part, "present_contact > 4";

    }

    # Skip old members
    push @where_part, "member_level > 0";

    if( $order eq "latest_in desc" )
    {
	push @where_part, "latest_in is not null";
	
    }


    if( $dist or $order eq 'dist')
    {
	my( $x, $y );

	my $plist = Para::Place->by_name( $place );
	if( @$plist > 1)
	{
	    die "Fick flera träffar för angiven plats\n";
	}
	elsif( @$plist == 1 )
	{
	    my $p = $plist->[0];
	    $x = $p->geo_x;
	    $y = $p->geo_y; # ;;;
	    unless( $x and $y )
	    {
		throw('notfound', "Vi vet inte var $place är någonstans\n");
	    }
	    debug 3, "Hittade platsen $place\n";
	}
	else
	{
	    my $mlist = Para::Member->by_name( $place, 0, 1 );
	    if( @$mlist > 1 )
	    {
		die "Fick flera träffar för angiven person\n";
	    }
	    elsif( @$mlist == 1 )
	    {
		my $m = $mlist->[0];
		$x = $m->geo_x;
		$y = $m->geo_y; # ;;;
		unless( $x and $y )
		{
		    throw('notfound', "Vi vet inte var $place bor\n");
		}

		my $nickname = $m->nickname;
		debug 3, "Hittade person $nickname\n";
	    }
	    else
	    {
		throw('notfound', "Vet inte vad '$place' är för plats\n");
	    }
	}

	if( $dist )
	{
	    warn "Inom $dist km\n";
	    push @where_part, "sqrt(pow(geo_y - ?,2) + pow(geo_x - ?,2)) * 70866.66666666 < ?*1000";
	    push @where_data, $y, $x, $dist;

	    if( $Para::Frame::U->level < 41 )
	    {
		push @where_part, "present_contact >= 15";
	    }

	}

	if( $Para::Frame::U->level < 41 )
	{
	    push @select, "CASE WHEN present_contact < 15 THEN null ELSE (sqrt(pow(geo_y - $y,2) + pow(geo_x - $x,2)) * 70866.66666666) END as dist";
	}
	else
	{
	    push @select, "(sqrt(pow(geo_y - $y,2) + pow(geo_x - $x,2)) * 70866.66666666) as dist";
	}
    }


    my $where_string = join " and ", @where_part;

    my $part_select = join ", ", 'member', @select;
    my $sql = 'select '.$part_select.' from member where '.$where_string.
	" order by $order";
    my(@data) = ($sql, @where_data);


    my $values = join ", ",map defined($_)?"'$_'":'<undef>', @data;
#    debug "SQL: $values";

    # Remember to recrate the List object returned
    my $persons = $Para::dbix->cached_select_list(@data);

    $persons->set_page_size( $q->param('pagesize') || 20 );

###  TODO: Return memberr objects...
#    $persons->materialize_sub(sub{
#        Para::Member->get_by_id($_[0]->{'member'}, $_[0]);
#    });

    return $persons;
}


#################################################################

sub currently_online
{
    my( $this, $mode ) = @_;

    # mode 0 = public
    # mode 1 = anonymous
    # mode 2 = both

    $mode ||= 0;
    my $db = paraframe_dbm_open( $C_DB_ONLINE );
    my @list;
    if( $mode == 1 and $Para::Frame::U->level >= 41 )
    {
	foreach my $mid ( sort {$db->{$b} <=> $db->{$a}} keys %$db )
	{
	    unless( $mid =~ /^\d+$/ )
	    {
		debug( sprintf "Removed invalid key $mid (%s)",
		       $db->{$mid}||'<undef>');
		delete $db->{$mid};
		next;
	    }

	    my $m = $this->get_by_id($mid);
	    $m->{'member'} = $mid;
	    if( $m->present_activity < 10 or
		$m->present_contact < 5 )
	    {
		push @list, $m;
	    }
	}
    }
    elsif( $mode == 2 and $Para::Frame::U->level >= 41 )
    {
	foreach my $mid ( sort {$db->{$b} <=> $db->{$a}} keys %$db )
	{
	    unless( $mid =~ /^\d+$/ )
	    {
		debug( sprintf "Removed invalid key $mid (%s)",
		       $db->{$mid}||'<undef>');
		delete $db->{$mid};
		next;
	    }

	    my $m = $this->get_by_id($mid);
	    $m->{'member'} = $mid;
	    push @list, $m;
	}
    }
    else
    {
	foreach my $mid ( sort {$db->{$b} <=> $db->{$a}} keys %$db )
	{
	    unless( $mid =~ /^\d+$/ )
	    {
		debug( sprintf "Removed invalid key $mid (%s)",
		       $db->{$mid}||'<undef>');
		delete $db->{$mid};
		next;
	    }

	    my $m = $this->get_by_id($mid);
	    next if $m->present_activity < 10;
	    next if $m->present_contact < 5;
	    push @list, $m;
	}
    }
    return \@list;
}


######################################################

sub count_currently_online
{
    my $db = paraframe_dbm_open( $C_DB_ONLINE );
    return scalar keys %$db;

    
#    undef $ONLINE_COUNT if $ONLINE_COUNT||0 < 0;
#    unless( defined $ONLINE_COUNT )
#    {
#	my $rec = $Para::dbix->select_record("select count(member) as cnt from member where latest_in is not null and (latest_out is null or latest_in > latest_out)");
#	$ONLINE_COUNT = $rec->{'cnt'};
#    }
#    debug sprintf "Count online $ONLINE_COUNT (%s)", $_[0]->count_currently_online_dbm();
#    return $ONLINE_COUNT;
}


######################################################

sub suggest_nicknames
{
    my( $this, $first, $second, $altsgoal ) = @_;

    $first ||= [];
    $second ||= [];
    $altsgoal ||= 5;

    if( not UNIVERSAL::isa $first, "ARRAY" )
    {
	$first = [$first];
	unless( UNIVERSAL::isa $second, "ARRAY" )
	{
	    push @$first, $second;
	    undef $second;
	}
    }
    elsif( not UNIVERSAL::isa $second, "ARRAY" )
    {
	$second = [$second];
    }

    my @alts;
    my %altshash;

  CHECK:
    foreach my $baselist ($first, $second )
    {
	foreach my $addnums (0..3)
	{
	    foreach my $base ( @$baselist )
	    {
		$base =~ s/\@.*//;
		my $test = name2nick($base);
		if( $addnums )
		{
		    # Avoid nick0 and nick1
		    $test .= int(rand((10**$addnums)-2)+2);
		}
		next if $altshash{$test}++;
		next unless eval{ $this->validate_nick($test)};
		unless( $this->get_by_nickname($test) )
		{
		    push @alts, $test;
		    last CHECK if @alts >= $altsgoal;
		}
		
	    }
	}
    }

    if( @alts < $altsgoal )
    {
	my $randname = make_passwd();
	my $left = $altsgoal - scalar(@alts);
	push @alts, $this->suggest_nicknames([$randname],[],$left);
    }

    return @alts;
}






######################################################

sub name2nick
{
    my $name = $_[0];

    $name = lc($name);
    $name =~ tr/åäöéè ./aaoee__/;
    $name =~ s/[^a-z0-9_\-]//g;
    $name =~ s/(^_+|_+$)//g;
    return $name
}

sub name2chat_nick
{
    my $name = $_[0];

    $name =~ tr/åäöéèÅÄÖÉÈ ./aaoeeAAOEE__/;
    $name =~ s/[^a-zA-Z0-9_\-]//g;
    $name =~ s/(^_+|_+$)//g;
    return $name
}

sub trim_name
{
    my $ref = shift;
    if( ref $ref )
    {
	return undef unless defined $$ref;
	$$ref =~ s/( ^\s+ | \s+$ )//gx;
	$$ref =~ s/\s+/ /g;
	$$ref = substr($$ref,0,24);
	return $$ref;
    }
    else
    {
	return undef unless defined $ref;
	$ref =~ s/( ^\s+ | \s+$ )//gx;
	$ref =~ s/\s+/ /g;
	$ref = substr($ref,0,24);
	return $ref;
    }
}

# warn "Loaded Para::Member\n";

1;
