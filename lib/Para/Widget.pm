#  $Id$  -*-perl-*-
package Para::Widget;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se template widgets
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Carp;
use Template 2;
use Data::Dumper;
use Text::ParagraphDiff;
use List::Util qw( max min );

use locale;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Time qw( now );
use Para::Frame::Utils qw( debug get_from_fork );
use Para::Frame::Widget qw( rowlist jump );

use Para::Constants qw( :all );
use Para::Topic;
use Para::Member;
use Para::Place;

sub status2level
{
    my( $status ) = @_;

    return -1 if $status < 2;
    return  4 if $status == 2;
    return 11 if $status == 3;
    return 39 if $status == 4;
    return 41;
}

sub interest_next_step
{
    my( $tid, $mid, $attr ) = @_;

    die "deprecated";

    $mid ||= $Para::Frame::U->id;
    confess unless $tid;
    my $q = $Para::Frame::REQ->q;

    ###  TEMPORARY solution...
    $attr ||= {};
    my $next = {};

    my $m = Para::Member->get( $mid );
    my $t = Para::Topic->get_by_id( $tid );

    my $i = $Para::dbix->select_possible_record('from intrest where intrest_member=? and intrest_topic=?', $mid, $tid);
    my $status = $m->new_status;

    unless( $i )
    {
	# Create some intrest
	$q->param('t', $tid);
	$q->param('intrest_defined', 1);
	require Para::Action::interest_update;
	Para::Action::interest_update::handler();
	$i = $Para::dbix->select_possible_record('from intrest where intrest_member=? and intrest_topic=?', $mid, $tid);
     }

    my $step = $attr->{'step'} || 0;
    my $i_con = $step || $i->{'intrest_connected'} || 0;
    my $t_con = $step || $t->connected || 0 ;

    my $editor = ($status > 3) ? 100 : $i->{'editor'} || 0;
    my $intrest = $i->{'intrest'} || 0;

#    warn "Step: $step\n";

    # We now keep more values undefined regarding the intreset
    my $defined = $attr->{'defined'} || $i->{'intrest_defined'} || 0;

#    warn "Defined: $defined\n";

    my $redefine = $attr->{'redefine'} || 0;

    $next->{'t_title'} = $t->title;
    $next->{'t_text'} = $t->text;
    $next->{'t_file'} = $t->file;
    $next->{'connected'} = $t->connected;
    $next->{'status'} = $t->connected_status;

    # 1. Define relations 1-10
    # 2. Specify intrest
    # 3. Define relations 11-20
    # 4. Specify related intrests
    # 5. Define relations 21-50

    my $base = "/member/db";



    my $next_vault = max($t_con, $i_con) + 1;

    ## Only do step one if the text doesn't exist
    if( $next_vault == 1 )
    {
	$next_vault = 2 if $t->text;
	$next_vault = 2 if $defined >= 30;
    }

    if( $next_vault < 2 and $i_con < 10 )
    {
	die "fixme";
	$next->{'handler'} = $base.'/topic/connection/vault_'.$next_vault;
    }
    elsif( $defined < 30 or $redefine )
    {
	$next->{'handler'} = $base.'/person/interest/specify.tt';
    }
    elsif( $intrest > 50 and $defined < 90 )
    {
	$next->{'handler'} = $base.'/person/interest/specify_related.tt';
    }
    else
    {
	$next->{'handler'} = $base.'/person/inetrest/specify_list.tt';
    }

    $next->{'url'} = $next->{'handler'}."?tid=$tid";

    return $next;
}


sub select_persons
{
    my( $crits ) = @_;

    $crits ||= {};
    my $all = 0;
    $all = 1 if $crits->{'all'};

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $offset = $q->param('offset')||1;
    my $pagesize = $q->param('pagesize')||50;

    $pagesize = min($pagesize,50) if $Para::Frame::U->level < 11;

    $q->param('offset', $offset);
    $q->param('pagesize', $pagesize);

    if( $all )
    {
	$offset = 1;
	$pagesize = 100000;
    }

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

    my $interest_words = rowlist('interest');
    my( $interest_part,  @where_data, @where_part, @select );

    debug "Interest words: @$interest_words";

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
					jump('välj',
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
	warn "newsmail: $newsmail\n";
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
	    warn "Hittade platsen $place\n";
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
		warn "Hittade person $nickname\n";
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
	" order by $order limit ? offset ?";
    my(@data) = ($sql, @where_data, int($pagesize), int($offset-1));


    my $values = join ", ",map defined($_)?"'$_'":'<undef>', @data;
    debug "SQL: $values";

    my $persons = get_from_fork(sub{$Para::dbix->select_list(@data)});
    return $persons;
}

sub html_psi_factory
{
    my( $context ) = @_;
    return sub{ html_psi(shift, 0, $context) };    
}

sub html_psi_nolinks_factory
{
    my( $context ) = @_;
    return sub{ html_psi(shift, 1, $context) };
}

sub html_psi
{
    # text in $_[0]
    my $nolinks = $_[1];
    my $context = $_[2];

    # locale should have been set previously!


#    warn ". . . .\n";

    my( $intext, $links ) = insert_autolinks( \$_[0], $nolinks, $context );
#    warn "Raw text is now:\n$intext\n";
    $intext = CGI::escapeHTML( $intext );

#    $intext =~ s/\r?\n(\r?\n)+/<p>/g;
#    $intext =~ s/\r?\n/<br>/g;
#    $intext =~ s/<p>/\n\n<p>/g;
#    $intext =~ s/<br>/<br>\n/g;

    my $text = "";
    my $cnt = 1;
    my $old_indent = 0;
    my @type_stack = ();
    my $old_type = "";
    my $old_block = 1;
    while( $intext =~ /(.*?) *(?:\r?\n( *\r?\n)?|\Z)/g )
    {
	next unless $1;
	$_ = $1;

	# EXAMINE
	#
	my $indent = 0;
	my $type = "";
	my $block = $2 ? 1 : 0;

	if( s/^\|// )
	{
	    $type = 'pre';
	}
	else
	{
	    ## TABLE
	    if( /  \S+.*?(   +| *\t+ *)\S+/ )
	    {
		s/^  //;
		my @col = split(/(?:   +| *\t+ *)/);
		$type = 'table';
		my $row = "";
		foreach my $col ( @col )
		{
		    if( $col =~ s/\s*:$// )
		    {
			$row .= "<th class=\"colheader\">$col</th>";
		    }
		    elsif( $col =~ s/\*(.*?)\*/$1/ )
		    {
			$row .= "<th>$col</th>";
		    }
		    else
		    {
			$row .= "<td>$col</td>";
		    }
		}
		$_ = $row;
	    }

	    ## INDENT
	    if( /^((?:  )+)/ )
	    {
		$indent = int(length($1)/2);
	    }

	    ## UL
	    if( s/^ +\* +// )
	    {
		$type = 'uli';
	    }
	}

#	warn "\nIndent: $indent ($old_indent)  Type: $type ($old_type)\n";


	# BEFORE BLOCK
	#
	if( $indent > $old_indent )
	{
#	    warn "Indent from $old_indent to $indent\n";
	    foreach( 1 .. ($indent-$old_indent))
	    {
		push @type_stack, $old_type;
#		warn('  'x$#type_stack."+ $type\n");

		if( $type eq 'uli' )
		{
		    $text .= "<ul>\n";
		}
		elsif( $type eq 'table' )
		{
		    $text .= "<br clear=\"left\"><table>\n";
		}
		else
		{
		    $text .= "<blockquote>\n";
		}

		# We are now in the new type.
		# Old type does not matter until we back out
		$old_type = $type;
	    }
#	    warn "Old type is now $old_type\n";
	}
	elsif( $indent < $old_indent )
	{
	    foreach( 1 .. ($old_indent-$indent))
	    {
		if( $old_type eq 'uli' )
		{
		    $text .= "</ul>\n";
		}
		elsif( $old_type eq 'table' )
		{
		    $text .= "</table>\n";
		}
		else
		{
		    if( $block and not $old_block )
		    {
			$text .= "</p>\n"; ### PARAGRAPH
			$text .= "</blockquote>\n"x($old_indent-$indent);
			$old_block = 1;
		    }
		    else
		    {
			$text .= "</blockquote>\n"x($old_indent-$indent);
		    }
		}

#		warn('  'x$#type_stack."- $old_type\n");

		$old_type = pop @type_stack;
#	    warn "Old type is now $old_type\n";
	    }
	}

	if( $type ne $old_type )
	{
#	    warn('  'x$#type_stack."- $old_type\n");
#	    warn('  'x$#type_stack."+ $type\n");

	    if( $old_type eq 'uli' )
	    {
		$text .= "</ul>\n";
	    }
	    elsif( $old_type eq 'table' )
	    {
		$text .= "</table>\n";
	    }
	    elsif( $old_type eq 'pre' )
	    {
		$text .= "</pre>\n";
	    }
	    elsif( $indent )
	    {
		$text .= "</blockquote>\n";
	    }

	    if( $type eq 'uli' )
	    {
		$text .= "<ul>\n";
	    }
	    elsif( $type eq 'table' )
	    {
		$text .= "<br clear=\"left\"><table>\n";
	    }
	    elsif( $type eq 'pre' )
	    {
		$text .= "<pre>\n";
	    }
	    elsif( $indent )
	    {
		$text .= "<blockquote>\n";
	    }
	}

	# BEFORE BLOCK
	#
	s/\*{1,3}(.*?)\*{1,3}/<strong>$1<\/strong>/g;
	s/&quot;(.*?)&quot;/<em>$1<\/em>/g;


	# BLOCK
	#
#	warn "row: $_\n";
	if( $type eq 'uli' )
	{
	    $text .= "<li>$_</li>\n";
	}
	elsif( $type eq 'table' )
	{
	    $text .= "<tr>$_</tr>\n";
	}
	elsif( $type eq 'pre' )
	{
	    $text .= "$_\n";
	}
	else
	{
	    if( $old_block )
	    {
#		warn "New para: $_\n";
		$text .= "<p>$_"; ### PARAGRAPH
	    }
	    else
	    {
		$text .= "<br>$_"; ### PARAGRAPH
	    }

	    if( $block )
	    {
#		warn "Ending block with '$_'\n";
		$text .= "</p>\n\n"; ### PARAGRAPH
	    }
	    else
	    {
		$text .= "\n";
	    }
	}

	# AFTER BLOCK
	#
#	warn"HOOOOOO\n";

	# FIXUP
	#
	$old_indent = $indent;
	$old_type = $type;
	$old_block = $block;
	last if $cnt++ > 1000;
    }

    # Include last type
    push @type_stack, $old_type;
    while( defined(my $type = pop @type_stack) )
    {
#	warn('  'x$#type_stack."- $type\n");
	if( $type eq 'uli' )
	{
	    $text .= "</ul>\n";
	}
	elsif( $type eq 'table' )
	{
	    $text .= "</table>\n";
	}
	elsif( $type eq 'pre' )
	{
	    $text .= "</pre>\n";
	}
	elsif( $old_indent > 0 )
	{
	    $text .= "</blockquote>\n";
	}
	elsif( $old_block )
	{
	    $text .= "</p>\n\n"; ### PARAGRAPH

	}
	$old_indent --;
    }

#    warn "---------\n";


    return deploy_links( $text, $links );
}

sub new_entry
{
    my( $tid, $state ) = @_;

    debug(1,"New entry ".($tid||''));
    if( $state )
    {
	$Para::state = $state;
    }

    # locale should have been set previously!

    # Initialize with tid
    $Para::entry_links = {};

    if( $tid )
    {
	$Para::entry_links->{$tid} = 1;
    }

    # Initialize link DB if not done
    #
    unless( $Para::link_db )
    {
	# TODO - FIXME - Run in FORK  (initialize before req)

	my $stime = time; ### TIME

	my $sth = $Para::dbh->prepare(
	      "select talias, t, t_file, media_url, media_mimetype
               from talias, t LEFT JOIN media on t=media
               where t=talias_t and talias_active is true
               and t_active is true and talias_autolink is true");

	$sth->execute();
	while( my( $alias, $tid, $file, $url, $mime ) = $sth->fetchrow_array )
	{
	    next unless $file; ### Ignore words without file
	    my @words = $alias =~ /(\W*\w+)\W*/g;
	    unless( @words )
	    {
		@words = ( $alias );
	    }

	    die "talias $alias has no tid" unless $tid;
#	    die "t $t has alias with no content" unless $alias =~ /\w/;
#	    $alias = '?' unless $alias =~ /\w/;

#	    if( $alias =~ /^"test/ )
#	    {
#		warn "Setting [$#words]{$words[0]}{$alias}\n";
#		sleep 5;
#	    }

	    debug(6,"W0 $words[0] A $alias T $tid F $file");
	    unless( length($words[0]) and length($alias) )
	    {
		warn "STRANGE ALIAS: W0 $words[0] A $alias T $tid F $file";
	    }

	    # Multiple topics for alias?
	    if( $Para::link_db->[$#words]{$words[0]}{$alias} )
	    {
		unless( $Para::link_db->[$#words]{$words[0]}{$alias}{'multi'} )
		{
		    $Para::link_db->[$#words]{$words[0]}{$alias}{'multi'} = $alias;
		}
	    }
	    else
	    {
		if( $mime and $mime =~ /^text/ )
		{
		    $file = $url;
		}

		$Para::link_db->[$#words]{$words[0]}{$alias} =
		{
		 tid => $tid,
		 file => $file,
		 alias => $alias,
		};
	    }

#	    if( $#words )
#	    {
#		warn "Add $#words -> $words[0] -> $alias\n";
#	    }
	}
	$sth->finish;
	debug(1,sprintf "link_db init in %2.2f second", (time-$stime));
    }
}

sub insert_autolinks
{
    my( $textref, $nolinks, $context ) = @_;

    # locale should have been set previously!

    return "" unless $textref and length $$textref;

    my @links = ();

    # Escape formatting for »...«
    #
    insert_format_quotes( $textref, \@links );

    return( $$textref, \@links ) if $nolinks;


    # Insert explicit links
    #
    insert_explicit_links( $textref, \@links, $context );

    # Link e-mail addresses
    #
    insert_email_links( $textref, \@links );

    # Link web addresses
    #
    insert_web_links( $textref, \@links );

#    warn "4 $text\n";

    my $text = $$textref;

    # Insert auto-links
    #
    for( my $size=$#$Para::link_db; $size >= 0; $size -- )
    {
	debug(3,"***** Size $size");
	$text =~ /(\s*)/gc;
	my $newtext = $1 || "";
	while( $text =~ /(\W*\w+)([^\s\w]*\s*)/gc ) #iterate failsafe
	{
	    my $match = $1;
	    my $middle = $2 || "";
	    my $debug_ra_text = ""; # DEBUG

	    # Don't touch ¤ in text
	    if( $match =~ /¤/ )
	    {
		$newtext .= $match . $middle;
		next;
	    }

	  STARTMATCH:
	  {
	      while(1)
	      {
		  $debug_ra_text .= "Analyze '$match' followed by '$middle'\n" if debug;
		  if( my $try = $Para::link_db->[$size]{lc($match)} )
		  {
		      debug(3,"$debug_ra_text  Checking $match");
		      my $pos = pos($text);
		      #		warn " - perform matching on '$text'\n";
		      if( $size and $text =~ /((?:\w+(?:\W+|$)){$size})/gc )
		      {
			  my $rest = $1;
			  my $last = "";
			  if( $rest =~ s/(\s+)$// )
			  {
			      $last = $1;
			  }
			  my $looking = $match . $middle . $rest;

			  # Look through all alternative nonletter ending
			SEARCH:
			{
			    while(1)
			    {
				debug(3,"  looking for $looking");
				if( my $rec = $try->{lc($looking)} )
				{
				    if( $rec->{'tid'} and $Para::entry_links->{$rec->{'tid'}} ++ )
				    {
					# This text has laready been linked
					push @links, $looking;
					$newtext .= "¤$#links¤$last";
				    }
				    else
				    {
					debug(3,"    Matched $looking!");
					push @links, set_autolink( $rec, $looking );
					$newtext .= "¤$#links¤$last";
				    }
				    last SEARCH;
				}

				if( $looking =~ /^(.*)(\W)$/s )
				{
				    $looking = $1;
				    $last = $2 . $last;
				}
				else
				{
				    last;
				}
			    }

			    # No match for any version
			    pos($text) = $pos;
			    $newtext .= $match . $middle;
			}
		      }
		      elsif( not $size )
		      {
			  # Include nonletters in the word to match;
			  if( $middle =~ /^(\S+)(.*)/s )
			  {
			      $match .= $1;
			      $middle = $2;
			  }

#			  warn "    - Starting with match='$match', middle='$middle'\n";

			SEARCH:
			{
			    while(1)
			    {
				debug(3,"  looking for $match");
				if( my $rec = $try->{lc($match)} )
				{
				    if( $rec->{'tid'} and $Para::entry_links->{$rec->{'tid'}} ++ )
				    {
					# This text has laready been linked
					push @links, $match;
					$newtext .= "¤$#links¤$middle";
				    }
				    else
				    {
					debug(3,"    Matched $match!");
					push @links,  set_autolink( $rec, $match );
					$newtext .= "¤$#links¤$middle";
				    }
				    last SEARCH;
				}

				if( $match =~ /^(.*)(\W)$/s )
				{
				    $match = $1;
				    $middle = $2 . $middle;
#				    warn "    - Middle is now '$middle'\n";
				}
				else
				{
#				    warn "    - Final match='$match', middle='$middle'\n";
				    last;
				}
			    }

			    # No match for any version
			    pos($text) = $pos;
			    $newtext .= $match . $middle;
			}
		      }
		      else
		      {
			  # No match
			  pos($text) = $pos;
			  $newtext .= $match . $middle;
		      }

		      last STARTMATCH;
		  }

		  if( $match =~ /^(\W)(.*)/s )
		  {
		      $newtext .= $1;
		      $match = $2;
		  }
		  else
		  {
		      last;
		  }
	      }

	      # No match for start of string
	      $newtext .= $match . $middle;
	  }
	}
	$text = $newtext;
	    debug(3,"text: '$text'");
    }


#    warn "5 $text\n";

    return( $text, \@links );
}

sub insert_format_quotes
{
    my( $textref, $linkref ) = @_;

    my $newtext = "";
    while( $$textref =~ /\G(.*?)\»(.*?)\«/sgc ) #iterate failsafe
    {
	$newtext .= $1;
	my $quote = CGI::escapeHTML( $2 );
	push @$linkref, $quote;
	$newtext .= "¤$#$linkref¤";
    }
    $newtext .= substr( $$textref, pos($$textref)||0);
    $$textref = $newtext;
}

sub insert_email_links
{
    my( $textref, $linkref ) = @_;

    my $newtext = "";
    while( $$textref =~ /\G(.*?)([\w\-\.]+\@[\w\-\.]+\.\w{2,3}\b)/sgc ) #iterate failsafe
    {
	$newtext .= $1;
	push @$linkref, "<a href=\"mailto:$2\">$2</a>";
	$newtext .= "¤$#$linkref¤";
    }
    $newtext .= substr( $$textref, pos($$textref)||0);
    $$textref = $newtext;
}

sub insert_web_links
{
    my( $textref, $linkref ) = @_;

    my $newtext = "";
    while( $$textref =~ /\G(.*?)((?:https?|ftp):\/\/)([\w\-\.]+\.(\w\w|com|net|org|edu|gov|mil|info)\b(?::\d+)?(?:\/[\w~\-\.\/]*)?(?:\?[\w&%=]+)?)/sgc ) #iterate failsafe
    {
	$newtext .= $1;
	my $link = $2.$3;
	push @$linkref, link_page($link, $link);
	$newtext .= "¤$#$linkref¤";
    }
    $newtext .= substr( $$textref, pos($$textref)||0);
    $$textref = $newtext;
}

sub insert_explicit_links
{
    my( $textref, $linkref, $context ) = @_;

    my $newtext = "";
    my( $pos );

    while( $$textref =~ /\G(.*?)(?:"([^"]+)"|(\w+))?\[(.*?)\]/sgc ) #"iterate failsafe
    {
	$newtext .= $1;
	$pos = pos( $$textref );
#	warn " -- pos $pos\n";
	my $name = $2 || $3 || '';
	my $target = $4;

	my $nametopics = Para::Topic->find( $name );
	my $targettopics = Para::Topic->find( $target );
	my $namehtml = CGI::escapeHTML($name);

	debug(3,"Finding explicit linking with '$name' to '$target'");

	my @topics;
	my $url;

	# Is name matching an alias?
	if( @$nametopics )
	{
	    debug(3,"Name matching an alias");
	    if( @$targettopics )
	    {
		debug(3,"  Targettopics exist");

		# 1. Select the nt that is the same as tt
		# 2. select the nt related to tt
		# 3. select tt


		foreach my $nt ( @$nametopics )
		{
		    foreach my $tt ( @$targettopics )
		    {
			if( $nt->has_same_id_as( $tt ) )
			{
			    push @topics, $nt;
			    debug(3,sprintf "    Specified topic added to primary: %s", $nt->desig);
			}
		    }
		}

		unless( @topics )
		{
		    foreach my $nt ( @$nametopics )
		    {
			foreach my $tt ( @$targettopics )
			{
			    if( $nt->has_rel([0,1,2,3], $tt ) )
			    {
				push @topics, $nt;
				debug(3,sprintf "    Related topic added to primary: %s", $nt->desig);
			    }
			}
		    }
		}

		unless( @topics )
		{
		    push @topics, @$targettopics;
		    debug(3,"  Setting targettopics as primary");
		}
	    }
	    else
	    {
		# 1. use URL
		# 2. fail
		if( $target =~ /^(http|\/)/ )
		{
		    debug(3,"  Use URL: $target");
		    $url = $target;
		}
	    }
	}
	else
	{
	    debug(3,"Name doesn't match an alias");
	    if( @$targettopics )
	    {
		debug(3,"  Targettopics exist");
		# 1. select tt
		push @topics, @$targettopics;
	    }
	    else
	    {
		# 1. use URL
		# 2. fail
		if( $target =~ /^(http|\/)/ )
		{
		    debug(3,"  Use URL: $target");
		    $url = $target;
		}
	    }
	}

	if( $url )
	{
	    debug(3,"Inserting link to $url with name $name");
	    push @$linkref, link_page($url, $name);
	    $newtext .= "¤$#$linkref¤";
	}
	elsif( @topics )
	{
	    my $tref = primary_choice( \@topics );
	    if( @$tref > 1 )
	    {
		my @tids = map "tid=".$_->id, @$tref;
		debug(3,"Inserting link to several files with name $name");
		my $tids = join '&', @tids;
		push @$linkref, "<a href=\"/search/alternatives.tt?run=topic_search_published&$tids\">$namehtml</a>";
		$newtext .= "¤$#$linkref¤";
	    }
	    else
	    {
		my $t = $tref->[0];
		if( $t->media )
		{
		    my $url = $t->media_url;
		    if( $t->media_type =~ /^image/ )
		    {
			debug(3,"Inserting image $url");
			if( $namehtml )
			{
			    push @$linkref, "<img alt=\"$namehtml\" src=\"$url\" class=\"inline_image\">";
			}
			else # Image to be put on separate row
			{
			    my %params = %$Para::Frame::PARAMS;
			    $params{'t'} = $t;
			    unless( $context )
			    {
				confess "Called without context";
			    }
			    my $block = $context->process("static/default/spacy_image.tt", \%params);
			    push @$linkref, $block;
			}
			$newtext .= "¤$#$linkref¤";
		    }
		    else
		    {
			if( $name )
			{
			    push @$linkref, link_page($url, $name);
			}
			else
			{
			    $name ||= $t->desig;
			    push @$linkref, '['.link_page($url, $name).']';
			}

			debug(3,"Inserting media link to $url with name $name");
			$newtext .= "¤$#$linkref¤";
		    }
		}
		else
		{
		    my $file = $t->file;
		    if( $name )
		    {
			push @$linkref, "<a href=\"$file\">$namehtml</a>";
		    }
		    else
		    {
			$name = $target;
			$namehtml = CGI::escapeHTML($name);
			push @$linkref, "[<a href=\"$file\">$namehtml</a>]";
		    }
		    debug(3,"Inserting nonmedia link to $file with name $name");
		    $newtext .= "¤$#$linkref¤";
		}
	    }
	}
	elsif( not length $target )
	{
	    # Another way to keep string from autolinking
	    push @$linkref, $namehtml;
	    $newtext .= "¤$#$linkref¤";
	}
	else
	{
	    debug(3,"No topics or URL found.  Leaving text");
	    my $targethtml =  CGI::escapeHTML($target);
	    push @$linkref, "\"$namehtml\"[$targethtml]";
	    $newtext .= "¤$#$linkref¤";
	}
    }
#    warn sprintf " -- Adding text from pos $pos: '%s'\n", substr( $$textref, $pos||0);
    $newtext .= substr( $$textref, $pos||0);

    $$textref = $newtext;
}

sub link_page
{
    my( $url, $name ) = @_;

    my $namehtml = CGI::escapeHTML($name);
    my $extra = "";

    if( $url =~ /^http:\/\/paranormal\.se\/(.*)/ )
    {
	$url = "/$1";
    }
    else
    {
	$extra .= " target=\"external\"";
    }

    return "<a href=\"$url\"$extra>$namehtml</a>";
}

sub primary_choice
{
    my( $topics ) = @_;

    # Try to bring number of topics down to 1.  But if we can't, leave
    # all topics in.

    if( @$topics == 1 )
    {
	return $topics;
    }

    debug(2,sprintf("Having a choice between %s\n",  join ' and ', map $_->desig, @$topics));

    my @nt = ();

    # 1. include non-media
    # 2. include non-url-media

    my $media = Para::Topic->get_by_id( T_MEDIA );

    foreach my $t ( @$topics )
    {
	debug(1,sprintf "Consider %d: %s", $t->id, $t->desig);
	next if $t->media;
	next if $t->has_rel(1, $media);
	debug(1,sprintf "  Including %s", $t->desig);
	push @nt, $t;
    }

    unless( @nt )
    {
	foreach my $t ( @$topics )
	{
	    debug(1,sprintf "2nd consider %d: %s", $t->id, $t->desig);
	    next if $t->media;
	    debug(1,sprintf "  Including %s", $t->desig);
	    push @nt, $t;
	}
    }

    if( @nt == 1 )
    {
	return \@nt;
    }
    else
    {
	return $topics;
    }
}

sub deploy_links
{
    my( $text, $links ) = @_;

    while( $text =~ s!¤(\d+)¤! $links->[ $1 ] !e ){};
    return $text;
}

sub set_autolink
{
    my( $rec, $text ) = @_;

    if( $rec->{'multi'} )
    {
	my $alias = $rec->{'multi'};
	my $topics = Para::Topic->find( $alias );
	$topics = primary_choice( $topics );

	if( @$topics > 1 )
	{
	    $rec =
	    {
	     talias => CGI::escapeHTML($alias),
	    };
	}
	else
	{
	    my $t = $topics->[0];
	    my $file = $t->file;
	    if( $t->media and $t->media_type =~ /^text/ )
	    {
		$file = $t->media_url;
	    }

	    $rec =
	    {
	     tid => $t->id,
	     file => $file,
	    };
	}
    }


    if( $Para::state and $Para::state eq 'static' )
    {
	if( $rec->{'talias'} )
	{
	    return "<a href=\"/search/alternatives.tt?run=topic_search_published&talias=$rec->{'talias'}\">$text</a>";
	}
	else
	{
	    return "<a href=\"$rec->{'file'}\">$text</a>";
	}
    }
    else
    {
	if( $rec->{'talias'} )
	{
	    return "<a href=\"/member/db/topic/view/?talias=$rec->{'talias'}\">$text</a>";
	}
	else
	{
	    return "<a href=\"/member/db/topic/view/?tid=$rec->{'tid'}\">$text</a>".
	      "<small><sup><a href=\"/member/db/topic/edit/aliases?tid=$rec->{'tid'}\">a</a></sup></small>";
	}
    }
}

sub diff
{
    my( $old, $new ) = @_;

    $old ||= '';
    $new ||= '';


#    return Text::ParagraphDiff::create_diff( \$old, \$new );
#    warn "Old: $old\n";
#    warn "New: $new\n";
    return Text::ParagraphDiff::create_diff( [map $_ ? $_ : '', split /\r?\n/, $old], [map $_ ? $_ : '', split /\r?\n/, $new] );
}

sub tfilter_init
{
    # Create the tfilter hashref
    my $q = $Para::Frame::REQ->q;

    my $tfilter =
    {
      include_inactive  => $q->param('include_inactive')||0,
      include_false     => $q->param('include_false')||0,
      include_indirect  => $q->param('include_indirect')||0,
      include_rev       => $q->param('include_rev')||0,
    };
    $tfilter->{'active'} = ! $tfilter->{'include_inactive'};
    $tfilter->{'true'} = ! $tfilter->{'include_false'};
    $tfilter->{'direct'} = ! $tfilter->{'include_indirec'};
    $tfilter->{'exclude_rev'} = ! $tfilter->{'include_rev'};

    return $tfilter;
}

1;
