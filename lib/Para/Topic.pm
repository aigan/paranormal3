#  $Id$  -*-perl-*-
package Para::Topic;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Topic class
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
use base qw( Exporter );
use Data::Dumper;
use Carp qw( cluck croak );
use locale;
use Date::Manip;
use IO::LockedFile;
use Template::Context;
use Sys::CpuLoad;
use Image::Size;
use Clone qw( clone );

BEGIN
{
    our @EXPORT_OK = qw( title2url );
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::DBIx qw( pgbool );
use Para::Frame::Utils qw( deunicode trim throw minof debug );
use Para::Frame::Time;
use Para::Frame::Widget;

use Para::Arcs;
use Para::Arc;
use Para::Member;
use Para::TS;
use Para::Alias;
use Para::Constants qw( :all );
use Para::Widget;

use constant BATCH => 3;

#
# CONSTRUCTOR
#
sub get
{
    return shift->new(@_);
}

sub get_by_id  # Use this primarely
{
    my( $class, $tid, $v ) = @_;
    $v ||= "";
    return $Para::Topic::CACHE->{"$tid-$v"} ||
	$class->_new( $tid, $v );
}

sub _new
{
    my( $this, $tid, $v, $nocache ) = @_;
    my $class = ref($this) || $this;

    return undef unless $tid;
#    croak "undefined tid" unless $tid;

    $v ||= ""; # Suitable for key part

    # This is maby already a topic
    return $tid if ref $tid eq 'Para::Topic';

    debug(1, "looking for $tid-$v");

    my $rec;
    unless( $nocache )
    {
	$rec = $Para::Topic::CACHE->{"$tid-$v"};
	if( $rec )
	{
#	warn "Got $rec from cache\n" if $DEBUG;
	    return $rec;
	}
    }

    if( $v )
    {
	$rec = $Para::dbix->select_possible_record("from t LEFT JOIN media on t=media where t=? and t_ver=?", $tid, $v);
    }
    else
    {
	$rec = $Para::dbix->select_possible_record("from t LEFT JOIN media on t=media where t=? order by t_active desc, t_status desc, t_ver desc", $tid);
	$v = $rec->{'t_ver'};
    }

    if( $rec )
    {
	# EXTRA DATA
	#
	$rec->{'maby_loopy'} = 1;

	my $t = $Para::Topic::CACHE->{"$tid-$v"} = bless($rec, $class);
	if( $t->active )
	{
	    $Para::Topic::CACHE->{"$tid-"} = $t;
	}
	warn "Initialized $tid-$v\n";
	return $t;
    }
    else
    {
	return $Para::Topic::CACHE->{"$tid-$v"} = undef;
    }
}

sub create
{
    my( $this, $title ) = @_;
    my $class = ref($this) || $this;

    trim( \$title );
    length( $title ) or throw('incomplete', "Titel saknas");
    my $m = $Para::Frame::U;

    if( $m->level < 5 )
    {
	throw('denied', "Du måste bli medborgare för att få skapa nya ämnen.");
    }

    # Do not allow duplicated
    if( $m->level < 11 and $Para::dbix->select_possible_record('from t where t_title = ?', $title) )
    {
	throw('denied', "Det finns redan ett ämne med denna titel.\n");
    }

    my $tid = $Para::dbix->get_nextval( "t_seq" );
    my $sth = $Para::dbh->prepare_cached("insert into t
                          ( t, t_title, t_urlpart, t_created,
                            t_updated, t_createdby,
                            t_changedby, t_status, t_active )
           values ( ?, ?, ?, now(), now(), ?, ?, ?, 't')");
    $sth->execute( $tid, $title, title2url($title), $m->id, $m->id,
		   $m->new_status );

    my $t = Para::Topic->get_by_id( $tid );
    $t->generate_url;

    $m->score_change('topic_submitted', 1);

    return $t;
}

###################  Class static methods

sub find_urlpart
{
    my( $this, $name ) = @_;
    my $class = ref($this) || $this;

    trim( \$name );
    my $recs = $Para::dbix->select_list('from t, talias where t=talias_t and talias_urlpart = lower(?) and t_active is true and t_entry is false and talias_active is true', $name );
    my @topics = map Para::Topic->get_by_id( $_->{'t'} ), @$recs;

    return \@topics;
}

=head2 find_by_alias

  Para::Topic->find_by_alias( $name, $crits )

crits:
  active
  status_min

crits apply both to the alias and the topic

=cut

sub find_by_alias
{
    my( $this, $name, $crits ) = @_;
    my $class = ref($this) || $this;

    debug(3,"Finding topic by alias $name",1);

    my $aliases = Para::Alias->find_by_name( $name, $crits );

    my $crit_active = $crits->{'active'};
    my $crit_status_min = $crits->{'status_min'} || 0;
    

    my @topics;
    foreach my $a ( @$aliases )
    {
	my $t = $a->topic;

	debug(4,"checking ".$t->desig);

	if( $crit_active )
	{
	    next unless $t->active;
	}

	next unless $t->status >= $crit_status_min;

	debug(4,"  passed");
	push @topics, $t;
    }

    debug(-1);
    return \@topics;
}


sub find
{
    my( $this, $name ) = @_;
    my $class = ref($this) || $this;

    if( UNIVERSAL::isa $name, 'Para::Topic' )
    {
	return [$name];
    }

    trim( \$name );
    return [] unless length $name;
    my( $recs );

    if( $name =~ /^(\d+)($| |:)/ and
	   my $rec = $Para::dbix->select_possible_record('from t where t = ? order by t_active desc,
                                             t_status desc, t_ver desc', $1 ) )
    {
	$recs = [$rec];
	debug(1,"found '$name' as topic id");
	# done
    }
    elsif( $recs = $Para::dbix->select_list('from t, talias where t=talias_t and talias = lower(?)
                                and t_active is true and t_entry is false
                                and talias_active is true', $name )
	   and @$recs)
    {
	if(debug)
	{
	    debug(1,"found '$name' as alias for active topic");
	    foreach my $rec (@$recs)
	    {
		debug(2,"  Topic id: $rec->{t} v$rec->{t_ver}");
	    }
	}
	#done
    }
    # include inactive topics
    elsif( $recs = $Para::dbix->select_list('from t as main, talias where t=talias_t and talias = lower(?)
                                and t_entry is false and t_active is false
                                and t_ver=(select max(t_ver) from t where t=main.t)', $name )
	   and @$recs)
    {
	my @res = @$recs;

	debug(1,"found '$name' as alias for inactive topic");

	if( my $recs2 = $Para::dbix->select_list('from t where lower(t_title)=lower(?)
                                 and t_active is true and t_entry is false', $name ) )
	{
#	    warn "  found titles\n";
	    foreach my $rec ( @$recs2 )
	    {
#		warn "    Look at $rec->{'t'}\n";
	    ADD:
		{
		    foreach( @res )
		    {
#			warn "      Compare with $_\n";
			last ADD if $_->{'t'} == $rec->{'t'};
		    }
#		    warn "    Add $rec->{'t'}\n";
		    push @res, $rec;
		}
	    }
	}

	my @topics = map Para::Topic->get_by_id( $_->{'t'}, $_->{'t_ver'} ), @res;
#	warn "  return\n";
	return \@topics;
    }
    # last resort
    elsif( $recs = $Para::dbix->select_list('from t where lower(t_title)=lower(?)
                                and t_active is true and t_entry is false', $name )
	   and @$recs)
    {
	debug(1,"found '$name' as topic title");
	#done
    }

    my @topics = map Para::Topic->get_by_id( $_->{'t'}, $_->{'t_ver'} ), @$recs;

    return \@topics;
}


sub find_one
{
    my( $this, $name ) = @_;
    my $class = ref($this) || $this;

    croak "No name given" unless $name;
    my $topics = Para::Topic->find( $name );


    if( $topics->[1] )
    {
	my $res = $Para::Frame::REQ->result;
	$res->{'info'}{'alternatives'}{'list'} = $topics;
	$res->{'info'}{'alternatives'}{'name'} = $name;
	throw('alternatives', "Välj ett av dessa alternativ för ämnet '$name'");
    }
    unless( $topics->[0] )
    {
	$Para::Frame::REQ->result->{'info'}{'create_confirm'} = $name;
	throw('notfound', "Ämnet '$name' finns inte");
    }

    return $topics->[0];
}

sub vacuum_from_queue
{
    my( $this, $limit ) = @_;

    $limit ||= 6;
    my( $cnt ) = 1;
    my $seen = {};

    my $minr = $Para::dbix->select_record("select min(t_entry_imported) as min from t where t_active is true and t_entry is false");
    my $vts = $Para::dbix->select_list('select t from t where t_active is true and t_entry is false and t_entry_imported < ? limit ?', $minr->{'min'}+1, $limit, []);
    foreach my $rec ( @$vts )
    {
	my $t = Para::Topic->get_by_id( $rec->{'t'} );
	$t->vacuum($seen);

	unless( $cnt % BATCH )
	{
	    debug(1,"**** comitting at $cnt");
	    $Para::dbh->commit;
	}

	$cnt ++;
    }
    return --$cnt;
}

sub publish_from_queue
{
    my( $this, $limit ) = @_;

    $limit ||= 40;
    my( $cnt ) = 1;

    my $topics =  $Para::dbix->select_list("select t from t where t_published is false and t_active is true and t_entry is false order by t_updated limit ?", $limit, []);
    foreach my $rec ( @$topics )
    {
	my $tid = $rec->{'t'};
	my $t = Para::Topic->get_by_id( $tid );
	$t->publish;

	unless( $cnt % BATCH )
	{
	    debug(1,"**** comitting at $cnt");
	    $Para::dbh->commit;
	}
	$cnt ++;
    }
    return --$cnt;
}

################  Methods

sub reset
{
    shift->changed_all_versions;
}

sub changed  # Topic changed. Refresh from DB
{
    my( $t ) = @_;

    my $tid = $t->id;

    my $v   = $t->ver;
#    warn "  refresh $tid, v$v\n";
    my $rec = $Para::dbix->select_possible_record("from t LEFT JOIN media on t=media where t=? and t_ver=?", $tid, $v);

    if( not $rec )
    {
	delete $Para::Topic::CACHE->{"$tid-$v"};
	delete $Para::Topic::CACHE->{"$tid-"};
	$t = undef;
	return undef;
    }

    ###  Replace all parts of object
    #
    foreach my $key ( keys %$t )
    {
	delete $t->{$key};
    }
    foreach my $key ( keys %$rec )
    {
	$t->{$key} = $rec->{$key};
    }
    $rec->{'maby_loopy'} = 1;


    return $t;
}

sub changed_all_versions
{
    my( $t ) = @_;

    foreach my $ver (@{ $t->versions(1) })
    {
	$ver->changed;
    }
}

sub key
{
    my( $t ) = @_;

    my $v = $t->ver;
    my $tid = $t->id;

    $v ||= ""; # Suitable for key part
    return "$tid-$v";
}

sub topic
{
    # Find topic for entry
    #
    # - Return undef if this is a topic (Depended on by mark_unpublished() )
    #
    my( $t ) = @_;

    unless( $t->{'topic'} )
    {
	if( $t->{t_entry} )
	{
	    if( my $parent = $t->parent )
	    {
		if( $parent->{t_entry} )
		{
		    $t->{'topic'} = $parent->topic;
		}
		else
		{
		    $t->{'topic'} = $parent;
		}
	    }
	    elsif( my $previous = $t->previous )
	    {
		if( $previous->{t_entry} )
		{
		    $t->{'topic'} = $previous->topic;
		}
		else
		{
		    # Should never come to this!
		    $t->{'topic'} = $previous;
		}
	    }
	}
    }
    return $t->{'topic'};
}

sub top_entry
{
    # Find top entry for entry
    #
    # - Return undef if this is the top entry
    #
    my( $t ) = @_;

    unless( $t->{top_entry} )
    {
	if( $t->{t_entry} )
	{
#	    warn "Are there a previous entry to $t->{'t'}?\n";
	    if( my $previous = $t->previous )
	    {
		if( my $top = $previous->top_entry )
		{
		    return $t->{top_entry} = $top;
		}
		else
		{
		    return $t->{top_entry} = $previous;
		}
	    }

	    my $parent = $t->parent;
	    if( $parent and $parent->{'t_entry'} )
	    {
		my $grandparent = $parent->parent;
		if( $grandparent and $grandparent->{'t_entry'} )
		{
		    return $t->{top_entry} = $parent->top_entry;
		}
		else
		{
		    return $t->{top_entry} = $parent;
		}
	    }
	}
	$t->{top_entry} = undef;
    }
    return $t->{top_entry};
}

sub parent
{
    # Find parent for entry
    #
    my( $t ) = @_;

#    warn "  Parent of ".$t->id."($t) is ".($t->{'t_entry_parent'}||'null')."\n"; ## DEBUG

    if( my $p = $t->get_by_id( $t->{'t_entry_parent'} ) )
    {
	$p->break_entry_loop;
	return $p;
    }
    return undef;
}

sub next
{
    my( $t, $filter ) = @_;

    # Find next entry in chain
    #
    $filter ||= {};
    if( my $n = Para::Topic->get_by_id( $t->{'t_entry_next'} ) )
    {
	$n->break_entry_loop;

	if( not $n->active )
	{
	    return undef unless $filter->{'include_inactive'};
	}

	return $n;
    }
    return undef;
}

sub previous
{
    # Find previous entry in chain
    #
    my( $t, $args ) = @_;

    unless( exists $t->{'previous'} )
    {
	my $recs = $Para::dbix->select_list("from t where t_entry_next=? and t_status>=?", $t->id, S_PROPOSED );
	if( @$recs == 0 )
	{
	    return $t->{'previous'} = undef;
	}

	my $previous = $t->get_by_id( $recs->[0]{'t'}, $recs->[0]{'t_ver'} );

	# First try sorting out the official connection
	if( @$recs > 1 )
	{
	    my $active = [];
	    my $proposed = [];
	    foreach my $rec ( @$recs )
	    {
		my $v = $t->get_by_id( $rec->{'t'}, $rec->{'t_ver'} );
		if( $v->active )
		{
		    push @$active, $v;
		}
		else
		{
		    push @$proposed, $v;
		}
	    }

	    if( @$active > 1 )
	    {
		# Too many active previous.
		$t->break_previous;
		return $t->previous;
	    }
	    elsif( @$active == 1 )
	    {
		$previous = $active->[0];
	    }
	    elsif( @$proposed == 1 )
	    {
		$previous = $proposed->[0];
	    }
	    else
	    {
		# Chose the previous that has the highest status, or
		# the latest topic or latest version of that topic
		my @sorted = sort
		{
		    ( $b->status <=> $a->status ) ||
		      ( $b->id <=> $a->id ) ||
			( $b->ver <=> $a->ver )
		} @$proposed;
		$previous = $sorted[0];
	    }
	}

	if( $previous )
	{
	    if( $previous->active or $args->{'include_inactive'} )
	    {
		$t->{'previous'} = $previous;
		$previous->break_entry_loop unless $args->{'ignore_check'};
	    }
	}
    }
    return $t->{'previous'};
}

sub file
{
    # Find url of topic
    #
    my( $t, $file ) = @_;

    if( defined $file )
    {
	if( length $file )
	{
	    if(  $t->{'t_file'} and ($file eq $t->{'t_file'}) )
	    {
		return $file;
	    }
	}
	else # make filename undef
	{
	    $file = undef;

	    # If topic already has an undefined filename, we are done
	    #
	    unless( defined $t->{'t_file'} )
	    {
		return undef;
	    }
	}

	# Remove the old page
	#
	$t->remove_page;

	my $sth_update = $Para::dbh->prepare_cached("update t set t_file=? where t=? and t_active is true");
	$sth_update->execute($file, $t->{'t'});

	$t->{'t_file'} = $file;
	$t->changed;
	$t->publish; # Publish right now since the page got deleted

	return $t->{'t_file'}; # Could be undef
    }

    unless( defined $t->{'t_file'} )
    {
	$t->generate_url;
    }
    return $t->{'t_file'};
}

sub outline
{
    my( $t, $args ) = @_;

    unless( $t->{'outline'} )
    {
	my $max_length = 240;
	my $min_length = 60;

	my $title = $t->title;
	my $text = "";

	if( $title )
	{
	    $text .= $title;
	    if( length($title) < $min_length )
	    {
		$text .= "::: ";
	    }
	}

	if( length( $text ) < $min_length )
	{
	    my $ttext = $t->text || "";
	    $ttext =~ s/\n\s*$/\n/;
	    my $body =  substr( $ttext, 0, ($min_length - length($text)));

	    # Find good place to breake text
	    my $startpos = minof(($min_length - length($text)), length($ttext) );
#	    warn sprintf("Length of ttext is %d and startpos is %d\n", length($ttext), $startpos);
#	    warn "Constructing tail from pos $startpos to ($max_length - $min_length)\nfrom string '$ttext'\n";
	    my $tail = substr( $ttext, $startpos,
			       ($max_length - $min_length)
			       ) || "";
#	    warn "tail is [$tail]\n";

	    $text .= $body;

	    if( not length( $tail ) )
	    {
		$text .= "";
	    }
	    elsif( $tail =~ s/\n$//s )
	    {
		$text .= $tail;
	    }
	    elsif( $tail =~ s/\n.+/ .../s )
	    {
		$text .= $tail;
	    }
	    elsif( $tail =~ s/\..+/. .../s )
	    {
		$text .= $tail;
	    }
	    elsif( $tail =~ s/\s*(och|eller|men|,|:).*/.../s )
	    {
		$text .= $tail;
	    }
	    elsif( $tail =~ s/(.*) .+/$1.../s )
	    {
		$text .= $tail;
	    }
	    else
	    {
		$tail = '...';
		$text .= $tail;
	    }
	}
	$t->{'outline'} = $text;
    }
    return $t->{'outline'};
}

sub sysdesig
{
    my( $t ) = @_;

    return sprintf "%d: %s", $t->id, $t->desig;
}

sub desig
{
    # Return an apropriate designation of the topic
    #
    my( $t, $args ) = @_;
    #
    # props:
    #   tid

    my $tid = $t->id;
#    warn "Desig for $tid\n";

    # Use args as part of cache key or don't cache!
    unless( 0 )
    {
	$t->{'desig'} = undef; # Reset

	# Get designation from title
	#
	$t->{'desig'} = $t->{'t_title'};

	# Has a subtitle?
	#
	foreach my $arc ( @{ $t->rel({type=>15})->arcs } )
	{
	    $t->{'desig'} .= " - " . $arc->value;
	}

	# Belongs to topic?
	#
	if( $t->{'desig'} )
	{
	    if( my $topic = $t->topic )
	    {
#		warn "  Putting in topic ref in desig $tid\n";
		my $topic_desig = $topic->desig;
		$t->{'desig'} .= " (om $topic_desig)";
	    }
	}


	# Get designation from entry
	#
	unless( $t->{'desig'} )
	{
	    if( my $entry = $t->top_entry )
	    {
#		warn "  Putting in entry ref in desig $tid\n";
		my $edesig = $entry->desig;
		$t->{'desig'} = "En del av $edesig";
	    }
	}

	unless( $t->{'desig'} )
	{
	    if( my $topic = $t->topic )
	    {
#		warn "  Basin desig $tid on topic\n";
		my $tdesig = $topic->desig;
#		warn "  Got topic desig : $tdesig";
		$t->{'desig'} = "en text om $tdesig";
	    }
#	    else
#	    {
#		die "Failed to find topic for $t->{t}";
#	    }
	}

	unless( $t->{'desig'} )
	{
	    if( $t->{'t_entry'} )
	    {
		$t->{'desig'} = "Text $t->{t}";
	    }
	    else
	    {
		$t->{'desig'} = "Ämne $t->{t}";
	    }
	}


	if( $args->{'tid'} )
	{
#	    warn "  Adding tid to to $tid\n";
	    $t->{'desig'} = $t->id . ": " . $t->{'desig'};
	}
    }
    return $t->{'desig'};
}

sub rel
{
    # Getting active and true relations:
    #
    # Get relations between me and topic $tid
    #
    # $t->rel({topic => $tid})->arcs
    #
    # Get relations with reltype $rid
    #
    # $t->rel({type => $rid})->arcs
    #
    # Get direct relations with reltype $rid
    #
    # $t->rel({type => $rid, direct => 1})->arcs

    my( $t ) = shift @_;
#    warn "t->rel is now $t->{'rel'}\n";
    $t->{'rel'} ||= Para::Arcs->init_rel($t);

    return $t->{'rel'}->find( @_ );
}

sub rev
{
    # Get relation(s) between me and topic $rid
    # See rel()
    #
    my( $t ) = shift @_;
    $t->{'rev'} ||= Para::Arcs->init_rev($t);

    return $t->{'rev'}->find( @_ );
}

sub arcs
{
    my( $t, $props ) = @_;
    #
    # Find all arcs (also false / inactive ) unless {all => 0}
    # props can be: pred, obj, value, obj_name, all

    $props ||= {};
    unless( ref $props eq 'HASH' )
    {
	$props =
	{
	 pred => $props,
	};
    }

    my $subj = $t;
    my $pred = $props->{'pred'};
    my $obj_name = ( $props->{'obj'} ||
		     $props->{'value'} ||
		     $props->{'obj_name'} );
    $props->{'all'} = 1 unless defined $props->{'all'};

    return Para::Arc->find( $pred, $subj, $obj_name, $props );
}

sub arc
{
    my( $t, $props ) = @_;

    $props ||= {};
    unless( ref $props eq 'HASH' )
    {
	$props =
	{
	 pred => $props,
	};
    }

    $props->{'all'} = 0;
    
    return $t->arcs( $props );
}

sub rev_arc
{
    my( $t, $props ) = @_;

    $props ||= {};
    unless( ref $props eq 'HASH' )
    {
	$props =
	{
	 pred => $props,
	};
    }

    $props->{'all'} = 0;
    
    return $t->rev_arcs( $props );
}

sub rev_arcs
{
    my( $t, $props ) = @_;
    #
    # See arcs()

    $props ||= {};
    unless( ref $props eq 'HASH' )
    {
	$props =
	{
	 pred => $props,
	};
    }

    my $subj = $props->{'subj'};
    my $pred = $props->{'pred'};
    my $obj_name = $t;
    $props->{'all'} = 1 unless defined $props->{'all'};

    return Para::Arc->find( $pred, $subj, $obj_name, $props );
}

sub has_rev
{
    my( $t, $pred, $rev ) = @_;
    return $t->has_rel($pred, $rev, 'rev');
}

sub has_rel
{
    my( $t, $pred, $rel, $dir ) = @_;

    $dir ||= 'rel';

    $pred = [$pred] unless ref $pred eq 'ARRAY';
    foreach(@$pred)
    {
	/^\d+$/ or die "Pred $_ invalid";
    }

    my @rels;

    unless( ref $rel )
    {
	if( $rel =~ /^\d+$/ )
	{
	    @rels = $t->get_by_id( $rel );
	}
	elsif( $rel )
	{
	    debug(1,"Looking for related topic $rel");
	    my $rels_in = $t->find_urlpart( $rel );
	    if( @$rels_in == 1 )
	    {
		@rels = @$rels_in;
	    }
	    elsif( @$rels_in > 1 )
	    {
		# Exclude media, order by oldes
		my $media = Para::Topic->get_by_id( T_MEDIA );
		foreach my $rel2 ( sort { $a->{'t'} <=> $b->{'t'} } @$rels_in )
		{
		    debug(1,"  Consider ".$rel2->sysdesig);
		    next if $rel2->media;
		    next if $rel2->has_rel(1, $media);
		    push @rels, $rel2;
		}
	    }
	    else
	    {
		warn "  Related topic $rel not found\n";
		return 0;
	    }

	    if( debug )
	    {
		foreach my $rel2 ( @rels )
		{
		    warn "    Using ".$rel2->sysdesig."\n";
		}
	    }
	}
	else
	{
	    # FIXME: only looks att pred 0
	    if( $dir eq 'rev' )
	    {
		return $t->rev({ type => $pred->[0] })->size;
	    }
	    else
	    {
		return $t->rel({ type => $pred->[0] })->size;
	    }
	}
    }
    else
    {
	@rels = $rel;
    }

    return 0 unless @rels;

    debug(1,"See if ".$t->desig." has $dir @$pred to any of the rels");

    foreach my $rel_out ( @rels )
    {
	my $arcs;
	if( $dir eq 'rev' )
	{
	    $arcs = $t->rev({topic => $rel_out });
	}
	else
	{
	    $arcs = $t->rel({topic => $rel_out });
	}
	
	if( $arcs )
	{
	    foreach my $arc ( @{$arcs->arcs} )
	    {
		my $id = $arc->pred_id;
		return 1 if grep{ $id == $_ } @$pred;
	    }
	}
    }

    return 0;
}

sub set_parent
{
    my( $t, $parent ) = @_;

    ###   FIX: Work on your own session version
    my $st = "update t set t_entry_parent=?, t_updated=now(), t_changedby=? where t=? and t_ver=?";
    my $sth = $Para::dbh->prepare_cached( $st );
    my $mid = $Para::Frame::U->id;

    my $tid = $t->id;
    my $ver = $t->ver;
    my $result = "";

    my $parent_id = $parent ? $parent->id : undef;
    my $parent_id_str = $parent ? $parent_id : 'null';
    $t->{'t_entry_parent'} = $parent_id;
    $t->{'parent'} = $parent;
    $t->maby_loopy(1);

    $result .=  "  Set $tid v$ver - parent: $parent_id_str\n";
    $sth->execute( $parent_id, $mid, $tid, $ver );

    # Don't care about loops in t_previous since we now is changing that
    # That's why we get the obj ouerself
    if( my $t_previous = $t->previous({ignore_check=>1}) )
    {
#	warn "2A\n";
	$result .=  $t_previous->set_next(undef);
    }

    $t->changed;
    $parent->changed if $parent;
    $t->mark_publish;

    return $result;
}

sub set_next
{
    my( $t, $next ) = @_;

    ###   FIX: Work on your own session version
    my $st = "update t set t_entry_next=?, t_updated=now(), t_changedby=? where t=? and t_ver=?";
    my $sth = $Para::dbh->prepare_cached( $st );
    my $mid = $Para::Frame::U->id;

    my $tid = $t->id;
    my $ver = $t->ver;
    my $result = "";

    # Don't care about loops in old_next since we now is changing that
    # That's why we get the obj ouerself
    if( my $old_next = Para::Topic->get_by_id( shift->{'t_entry_next'} ) )
    {
#	warn "B\n";
	$old_next->{'previous'} = undef;
	warn "    Previous for ".$old_next->id." is now undef\n";
    }

    my $next_id = undef;
    my $next_id_str = 'null';
    if( $next )
    {
#	warn "C\n";
	$next_id = $next->id;
	$next_id_str = $next_id;
	if( my $next_previous = $next->previous )
	{
#	warn "D\n";
	    $result .= $next_previous->set_next( undef );
	}

	if( my $t_next = $t->next )
	{
#	warn "E\n";
	    $result .= $next->set_next( $t_next );
	}

	if( my $next_parent = $next->parent )
	{
#	warn "F\n";
	    $result .=  $next->set_parent(undef);
	}

	$next->{'previous'} = $t;
	$next->maby_loopy(1);
    }

    $result .=  "  Set $tid v$ver - next: $next_id_str\n";
    $sth->execute( $next_id, $mid, $tid, $ver );

    $t->{'t_entry_next'} = $next_id;
    $t->maby_loopy(1);

    $t->changed;
    $next->changed if $next;
    $t->mark_publish;

#    warn "G\n";
    return $result;
}

sub break_previous
{
    my( $t ) = @_;

    my $cnt = 0;
    my $recs = $Para::dbix->select_list("select t from t where t_entry_next=? and t_status>=? order by t_active desc, t_status desc, t desc, t_ver desc", $t->id, S_PROPOSED );
    # Sorted such that the first rec should keep t_entry_next

    my $rec = shift @$recs;
    my $pt = Para::Topic->get_by_id( $rec->{'t'} );
    warn sprintf "Break multipple previus for topic %d\n", $t->id;
    warn sprintf "  Keeping topic %d v%d\n", $pt->id, $pt->ver;

    foreach my $rec ( @$recs )
    {
	my $pt = Para::Topic->get_by_id( $rec->{'t'} );
	warn sprintf "  Decouple next from %d v%d\n", $pt->id, $pt->ver;
	$pt->set_next( undef );
	$cnt++;
    }
    return $cnt;
}

sub break_entry_loop
{
    my( $t ) = @_;
    return undef unless $t;

#    warn sprintf("Checking loopiness of %d\n", $t->id);

    return unless $t->{'maby_loopy'};

    my $tid = $t->id;
    my $ver = $t->ver;

    # We take care of it here
    $t->maby_loopy(0);

    # Start with simple cases?..
    if( $t->previous and $t->parent )
    {
	warn "Crossbranches for $tid v$ver detected\n";
	warn "  keeping the parent\n";
	$t->previous->set_next(undef);
    }

    # Complex cases
    if( $t->child_of( $t ) )
    {
	# LOOP DETECTED
	warn "Recursive loop for $tid v$ver detected\n";

	# Decouple
	warn "  Does $tid has a previous?\n";
	if( my $p = $t->previous )
	{
	    my $pid = $p->id;
	    warn "    Yes: $pid.  Decoupling\n";
	    warn $p->set_next(undef);
	    warn "    Decoupled $pid!\n";

	    ## CHECK
	    if( my $p = $t->previous )
	    {
		my $pid = $p->id;
		warn "      $tid ($t) STILL has $pid as previous!\n";
		die "Oh no!\n";
	    }
	}
	warn $t->set_parent(undef);

	if( $t->entry )
	{
	    # Add to Lost entries

	    my $le = Para::Topic->find_one('Lost entry');
	    warn $t->set_parent($le);
	    warn "  Placed $tid in the hall of lost entries\n";
	}
	else
	{
	    warn "  $tid has now become independant\n";
	}

	if( my $p = $t->parent )
	{
	    warn "  $tid has parent ".$p->id."\n";
	}
	if( my $n = $t->next )
	{
	    warn "  $tid has next   ".$n->id."\n";
	}
    }

    if( $t->follows( $t ) )
    {
	warn sprintf("Recursion loop detected for %d\n", $t->id );

	my $next = $t->next;
	$t->set_next(undef);

	my $first = $next->top_entry || $next;
	if( $t->follows( $first ) )
	{
	    unless( $first->topic )
	    {
		# Add to Lost entries
		my $le = Para::Topic->find_one('Lost entry');
		my $fid = $first->id;
		warn $first->set_parent($le);
		warn "  Placed $fid in the hall of lost entries\n";
	    }
	}
	else
	{
	    $t->set_next($first);
	}
    }
}

sub break_topic_loop
{
    my( $t, $involved, $level ) = @_;

    # Is this the base of the recursive tree?
    my $base = $involved ? 0 : 1;

    # For debugging:
    $level ||= 0;
    $level ++;
    debug(1,sprintf "%d: Level %d - Check %s", $$, $level, $t->desig);


    # Holds all involved topics
    $involved ||= {};

    # Do not process already involved topics
    return if $involved->{$t->id};
    $involved->{$t->id} ||= {};

    my $done = 0;
    my $limit = 8;
    while( not $done )
    {
	# Repeat until all loops breaken

	my $incomplete = 0; # All arcs not checked

	foreach my $arc ( @{$t->rel->arcs} )
	{
	    my $pred = $arc->pred;
	    next if $pred->id == 0; # reflexive pred

	    # Don't take to much at the time
	    my $cnt_topics = scalar  keys( %$involved );
#	    warn "Topics cnt: $cnt_topics\n";
	    if( $cnt_topics >= $limit )
	    {
		# This means that There could be more than one cut to
		# sever a topic loop, if it's big
		debug(1,sprintf "Check work limit ($limit)");


		# Only stop early if we have some (explicit) arcs
		my $cnt = 0;
		foreach my $t2id ( keys %$involved )
		{
		    $cnt += keys %{ $involved->{$t2id} };
		}

		if( $cnt >= 5 )
		{
		    $incomplete = 1;
		    debug(1,"$cnt arcs found. Stopping early");
		    last;
		}
		else
		{
		    # Work a little longer
		    debug(1,"$cnt arcs found. Raise limit");
		    $limit += 2;
		}
	    }


	    if( my $obj = $arc->obj )
	    {
		# Remove all self-referencing arcs
		if( $t->equals( $obj ) )
		{
		    $arc->remove('force');
		}

		# Sign of loop?
		elsif( my $arc2 = Para::Arc->find($pred, $obj, $t) )
		{
		    # $obj involved in loop. Process it
		    $obj->break_topic_loop( $involved, $level );

		    # remove indirect arcs. Even if explicit
		    #
		    if( $arc2->indirect )
		    {
			$arc2->remove('force');
		    }
		    else # direct and therefore explicit
		    {
			# Add the explicit arc
			$involved->{$obj->id}{$arc2->id} = $arc2;
		    }

		    if( $arc->indirect )
		    {
			$arc->remove('force');
		    }
		    else # direct and therefore explicit
		    {
			# Add the explicit arc
			$involved->{$t->id}{$arc->id} = $arc;
		    }
		}
	    }
	}

	# Time to resolve the links among the involved topics
	if( $base )
	{
	    # We want to deactivate the newest arc and see if that helped
	    debug(1,"Involved arcs rounded up");

	    my $arcs;
	    foreach my $t2id ( keys %$involved )
	    {
		foreach my $arc ( values %{ $involved->{$t2id} } )
		{
		    my $created = Date::Manip::ParseDateString( $arc->created );
		    $arcs->{ $arc->id } = $created;
		}
	    }

	    my @sorted = sort { $arcs->{$a} cmp $arcs->{$b} } keys %$arcs;

	    my $removed = 0;
	    foreach my $aid ( @sorted  )
	    {
		my $arc = Para::Arc->get( $aid );
		next unless $arc;

		# Deactivating the last explicit arc
		# We only added explicit arcs. No check needed
		# next unless $arc->explicit;

		debug(1, sprintf " Deactivating the arc %s in order to break loop", $arc->as_string);

		$arc->deactivate( S_DENIED );
		$removed ++;

		# Ee only want to deactivate the latest added arc
		last;
	    }

	    # Do another pass if anything was removed or not all the
	    # arcs was checked.  I.e: Keep checking until loop broken

	    unless( $removed or $incomplete )
	    {
		# No (explicit) arcs found. Clean up
		debug(1,"No arcs to deactivate. All done here");
		$done = 1;
	    }

	    debug(1,"Check involed topics");

	    # All seems fine now. Check arcs for involved topics
	    #
	    foreach my $t2id ( keys %$involved )
	    {
		my $t2 = Para::Topic->get_by_id( $t2id );
		debug(1,sprintf "  Check %s", $t2->desig);
		my $rel_arc_list = $t2->rel->arcs;
		my $rev_arc_list = $t2->rev->arcs;
		foreach my $arc ( @$rel_arc_list, @$rev_arc_list )
		{
		    $arc->vacuum;
		}
	    }

	    # Clean up for a new round
	    $involved = {};
	    $involved->{$t->id} = {};
	}
	else
	{
	    # We're not in the base of recursio. Done with this. On to
	    # the next branch
	    $done = 1;
	}
    }

#    # Special handling for now!!!!
#    warn "-----> commit\n";
#    $Para::dbh->commit;

}

sub create_new_version
{
    my( $t, $rec ) = @_; # Returns the new version

    my $m = $Para::Frame::U;
    my $mid = $m->id;

    my $m_status = $m->status;

    # We should replace the active/current version. not necessary this version
    my $current_t = $t->get_by_id($t->id);
    my $old_status = $current_t->status || S_PROPOSED;

    # Wanted result
    my $new_status = $m->new_status;
    my $new_active = 't';

    warn "Old status: $old_status\n";
    warn "New status: $new_status\n";
    warn "M   status: $m_status\n";


    if( $m_status < $old_status ) # New version is proposed
    {
	$new_status = S_PROPOSED;
	$new_active = 'f';
    }
    else # Old version is replaced
    {
	if( $current_t->active )
	{
	    $current_t->set_status( S_REPLACED );
	}
    }


    $rec ||= {};

    my $sth = $Para::dbh->prepare_cached(" insert into t ( t, t_pop,
             t_size, t_created, t_createdby, t_updated, t_changedby,
             t_status, t_title, t_title_short, t_title_short_plural,
             t_text, t_comment_admin, t_file, t_oldfile, t_urlpart,
             t_class, t_entry, t_entry_parent, t_entry_next,
             t_entry_imported, t_ver, t_connected, t_active,
             t_connected_status, t_replace, t_published ) values (
             ?,?,?,now(),?,now(),?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,(select
             max(t_ver)+1 from t where t=?),?,?,?,?,?)");

#    warn "title: $rec->{'title'}\n";
#    warn "short: $rec->{'short'}\n";
#    warn "plural: $rec->{'plural'}\n";

    undef $rec->{'short'} if $rec->{'short'} and $rec->{'short'} eq $rec->{'title'};
    undef $rec->{'plural'} if $rec->{'plural'} and $rec->{'short'} eq $rec->{'title'};
    undef $rec->{'short'} if $rec->{'short'} and length $rec->{'short'} > 50;
    undef $rec->{'plural'} if $rec->{'plural'} and length $rec->{'plural'} > 50;

    $sth->execute(
		    $t->id,
		    $t->{'t_pop'},
		    $t->{'t_size'},
		    $mid,
		    $mid,
		    $new_status,
		    defined $rec->{'title'} ? $rec->{'title'} : $t->{'t_title'},
		    defined $rec->{'short'} ? $rec->{'short'} : $t->{'t_title_short'},
		    defined $rec->{'plural'}? $rec->{'plural'}: $t->{'t_title_short_plural'},
		    $rec->{'text'} || $t->{'t_text'},
		    $rec->{'admin_comment'} || $t->{'comment_admin'},
		    $t->{'t_file'},
		    $t->{'t_oldfile'},
		    $rec->{'url'} || $t->{'t_urlpart'},
		    $t->{'t_class'},
		    $t->{'t_entry'},
		    $t->{'t_entry_parent'},
		    $t->{'t_entry_next'},
		    $t->{'t_entry_imported'},
		    $t->id, ### for calculating new version number   {'t_ver'}+1,
		    $t->{'t_connected'},
		    $new_active,
		    $t->{'t_connected_status'},
		    undef,
		    undef
		    );

    $t->changed_all_versions;

    ### Switch to new version
    # DOES NOT CHANGE CACHED TOPIC
    #
    my $ot = $t;
    $t = $ot->last_ver;

    $t->title2aliases( $t->title, 1 );
    $t->title2aliases( $t->real_short, 1 );
    $t->title2aliases( $t->real_plural );
    $t->generate_url;


    # Republish topics linking to/from if titles changed
    if( $t->title ne $ot->title or
	$t->short ne $ot->short or
	$t->plural ne $ot->plural )
    {
	foreach my $arc (@{$t->rel->arcs})
	{
	    next if $arc->indirect;
	    $arc->obj and $arc->obj->mark_unpublished;
	}

	foreach my $arc (@{$t->rev->arcs})
	{
	    next if $arc->indirect;
	    $arc->obj and $arc->subj->mark_unpublished;
	}
    }

    # Old cahced info about active and other versions are outdated
    # $t->reset; # Already done above

    $t->mark_publish;

    return $t;
}

sub set_status
{
    my( $t, $status, $m ) = @_;

    die "no status given" unless defined $status;

    $m ||= $Para::Frame::U;
    $m = Para::Member->get($m) unless ref $m;

    my $new_active = $status < S_PENDING ? 0 : 1;

    if( $new_active and not $t->active )
    {
	# Unactivate all other
	my $st = "update t set t_status=?,
                 t_active='f', t_updated=now(), t_changedby=?
                 where t=? and t_active is true";
	my $sth = $Para::dbh->prepare_cached( $st );
	$sth->execute(S_REPLACED, $m->id, $t->id);

	$m->score_change('accepted_thing');
	$t->created_by->score_change('thing_accepted');
    }

    unless( $new_active )
    {
	$m->score_change('rejected_thing');
	$t->created_by->score_change('thing_rejected');
    }

    my $st = "update t set t_status=?,
              t_active=?, t_updated=now(), t_changedby=?
              where t=? and t_ver=?";
    my $sth = $Para::dbh->prepare_cached( $st );
    $sth->execute($status, pgbool($new_active), $m->id, $t->id, $t->ver);

    warn sprintf "Status for %d v%d changed to %d\n", $t->id, $t->ver, $status;

    $t->changed_all_versions;
    $t->mark_publish;
}

#### Acessors

sub text    { shift->{'t_text'} }
sub id      { shift->{'t'} }
sub status  { shift->{'t_status'} }
sub oldfile { shift->{'t_oldfile'} }
sub entry   { shift->{'t_entry'} }
sub active  { shift->{'t_active'} }
sub created
{
    return $_[0]->{'created'} ||=
	Para::Frame::Time->get( $_[0]->{'t_created'} );
}

sub updated
{
    return $_[0]->{'updated'} ||=
	Para::Frame::Time->get( $_[0]->{'t_updated'} );
}


sub admin_comment { shift->{'t_comment_admin'} }

sub title   { shift->{'t_title'} }
sub short   { $_[0]->{'t_title_short'} || $_[0]->desig }
sub plural  { $_[0]->{'t_title_short_plural'} || $_[0]->desig }
sub real_short { $_[0]->{'t_title_short'} }
sub real_plural  { $_[0]->{'t_title_short_plural'} }

sub ver     { shift->{'t_ver'} }

sub link
{
    my( $t ) = @_;

    return &Para::Frame::Widget::jump( $t->desig, $t->file );
}

sub created_by
{
    Para::Member->get( shift->{'t_createdby'} || -1 );
}

sub updated_by
{
    Para::Member->get( shift->{'t_changedby'} || -1 );
}

sub member
{
    Para::Member->get_by_tid( shift->{'t'} );
}

sub ts_list
{
    Para::TS->rel_list( shift->id );
}

sub ts_revlist
{
    Para::TS->rev_list( shift->id );
}

sub media_url { shift->{'media_url'} }
sub media_type { shift->{'media_mimetype'} }
sub media { shift->{'media'} } # boolean

sub class { shift->{'t_class'} } # boolean

sub connected_status { shift->{'t_connected_status'} }
sub connected { shift->{'t_connected'} }

sub image_size_x
{
    my( $t ) = @_;

    my( $x, $y ) = $t->image_size_xy;
    return $x;
}

sub image_size_y
{
    my( $t ) = @_;

    my( $x, $y ) = $t->image_size_xy;
    return $y;
}

sub image_size_xy
{
    my( $t ) = @_;

    return undef unless $t->is_image;
    my $file = $t->media_url;
    $file =~ s/^http:\/\/(www\.)?paranormal\.se\b//;
    return undef unless $file =~ /^\//;
    
    my( $x, $y, $err ) = imgsize( "/var/www/paranormal.se".$file );
    $y or die $err;

    return( $x, $y );
}

=head2 aliases

  $t->aliases()

  $t->aliases(\%crits)

crits:
  active
  status_min

returns hashref of name=>alias pairs

=cut

sub aliases
{
    my( $t, $crits ) = @_;

    # Shared by all versions of topic
    unless( $Para::Topic::ALIASES{$t->id} )
    {
	return Para::Alias->find_by_tid( $t->id );
    }

    if( $crits )
    {
	my %res = ();

	my $crit_active = $crits->{'active'};
	my $crit_status_min = $crits->{'status_min'} || 0;

	foreach my $a ( values %{ $Para::Topic::ALIASES{$t->id} } )
	{
	    if( $crit_active )
	    {
		next unless $a->active;
	    }

	    next unless $a->status >= $crit_status_min;

	    debug(4,"    passed");
	    $res{$a->name} = $a;
	}
	return \%res;
    }

    return $Para::Topic::ALIASES{$t->id};
}


sub alias_list
{
    die "deprecated"; # Clean up!

    # topic, args = {include_inactive => 1}
    return Para::Alias->list(@_);
}

sub add_alias
{
    return Para::Alias->add(@_);
}

sub has_alias
{
    return $_[0]->aliases->{$_[1]};
}

sub alias
{
    return $_[0]->aliases->{$_[1]};
}

sub maby_loopy
{
    if( defined $_[1] )
    {
	$_[0]->{'maby_loopy'} = $_[1];
    }
    $_[0] ? $_[0]->{'maby_loopy'} : undef;
}


sub childs { shift->entry_list(@_) }
sub entry_list
{
    my( $t, $filter ) = @_;

    my $list;
    $filter ||= {};

    if( $filter->{'include_inactive'} )
    {
	$list = $Para::dbix->select_list("select t, max(t_status) as max_status from t where t_entry_parent=? group by t order by max_status desc, t asc", $t->id);
    }
    else
    {
	$list = $Para::dbix->select_list("select t from t where t_entry_parent=? and t_active is true order by t_status desc, t asc", $t->id);
    }
    my @entries;
    foreach my $rec ( @$list )
    {
	if( my $c = Para::Topic->get_by_id( $rec->{'t'} ) )
	{
	    $c->break_entry_loop;
	    push @entries, $c;
	}
    }
    return \@entries;
}

sub has_child
{
    my( $t, $filter ) = shift;

    my $rec;
    $filter ||= {};

    if( $filter->{'include_inactive'} )
    {
	$rec = $Para::dbix->select_possible_record("from t where t_entry_parent=?", $t->id);
    }
    else
    {
	$rec = $Para::dbix->select_possible_record("from t where t_entry_parent=? and t_active is true", $t->id);
    }

    return $rec ? 1 : 0;
}

sub child_of
{
    my( $t, $sup ) = @_;

    if( my $prev = $t->previous )
    {
	return 1 if $prev->id == $sup->id;
	return 1 if $prev->child_of( $sup );
    }

    if( my $parent = $t->parent )
    {
	return 1 if $parent->id == $sup->id;
	return 1 if $parent->child_of( $sup );
    }
    return 0;
}

sub follows
{
    my( $t, $prev ) = @_;

    if( my $n = $prev->next )
    {
	if( $n->id == $t->id )
	{
	    return 1;
	}
	else
	{
	    return $t->follows( $n );
	}
    }
    else
    {
	return 0;
    }
}

sub replace
{
    my( $t ) = @_;

    if( my $r_id = $t->{'t_replace'} )
    {
	return $t->get_by_id( $r_id );
    }
    return undef;
}

sub replaced_by
{
    my( $t ) = @_;

    unless( exists $t->{'replaced_by'} )
    {
	my $recs = $Para::dbix->select_list("from t where t_replace=?", $t->id);
	warn "Getting replaced_by for ".$t->id."\n";

	if( $recs->[0] )
	{
	    $t->{'replaced_by'} = $t->get_by_id( $recs->[0]->{'t'} );
	}
    }

    warn "replaced_by is ".($t->{'replaced_by'}||'undef')."\n";
    return $t->{'replaced_by'};
}

sub previous_ver
{
    my( $t ) = @_;

    my $ver = $t->ver - 1;

    return undef unless $ver > 0;
    return $t->get_by_id( $t->id, $ver );
}

sub first_ver
{
    my( $t ) = @_;

    return $t->get_by_id( $t->id, 1 );
}

sub next_ver
{
    my( $t ) = @_;

    return $t->get_by_id( $t->id, ($t->ver + 1) );
}

sub last_ver
{
    my( $t ) = @_;

    if( my $next = $t->next_ver )
    {
	return $next->last_ver;
    }

    return $t;
}

sub active_ver
{
    my( $t ) = @_;

    my $av = $t->get_by_id( $t->id );
    if( $av->active )
    {
	return $av;
    }
    return undef;
}

sub versions
{
    my( $t, $nocache ) = @_;

    my $versions = [];

    for(my $v=1; my $ver = $t->get_by_id($t->id, $v, $nocache); $v++)
    {
	push @$versions, $ver;
    }
    return $versions;
}

sub is_url_media
{
    my( $t ) = @_;

    if( $Para::dbix->select_possible_record('from media where media = ?', $t->id) )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub is_image
{
    my( $t ) = @_;

    return unless $t->media_type;
    if( $t->media_type =~ /^image\// )
    {
	return $t->media_type;
    }
    else
    {
	return '';
    }
}

sub title2aliases
{
    my( $t, $val, $index ) = @_;

    # Do not create aliases for entries
    return if $t->entry;

    return unless defined $val;
    trim(\$val);
    return unless length $val;

    my $m = $Para::Frame::U;

    $t->add_alias( $val,
		 {
		  index  => $index, # keep undef if undef
		  quiet  => 1,
		 });
}

sub delete_cascade
{
    my( $t ) = @_;

    # Authorization
    #
    if( $Para::Frame::U->level < 40 )
    {
	throw('denied', "Reserverat för mästare...");
    }

    # Things to delete
    #
    # 1. t
    # 2. talias
    # 3. intrest
    # 4. rel
    # 5. t.t_entry_parent
    # 6. ts
    # 7. media
    # Not supported: member, publ

    my $tid = $t->id;

    ### t
  {
      my $st = "update t set t_status=?,
                 t_active='f' where t=? and t_active is true";
      my $sth = $Para::dbh->prepare_cached( $st );
      $sth->execute( S_DENIED, $tid);
  }

    ### Aliases
  {
      my $st = "update talias set talias_status=?,
                 talias_active='f' where talias_t=?";
      my $sth = $Para::dbh->prepare_cached( $st );
      $sth->execute( S_DENIED, $tid );
  }

    ### Intrest
  {
      my $st = "delete from intrest where intrest_topic=?";
      my $sth = $Para::dbh->prepare_cached( $st );
      $sth->execute( $tid );
  }

    ### Rel
  {
      foreach my $rel (@{Para::Arc->find(undef, $t, undef,
				      {all=>1, active=>1})})
      {
	  next if $rel->indirect;
	  $rel->deactivate;
      }

      foreach my $rev (@{Para::Arc->find(undef, undef, $t,
				      {all=>1, active=>1})})
      {
	  next if $rev->indirect;
	  $rev->deactivate;
      }

      my $st1 = "update rel set rel_status=?,
                 rel_active='f' where rev=?";
      my $sth1 = $Para::dbh->prepare_cached( $st1 );
      $sth1->execute( S_DENIED, $tid );

      my $st2 = "update rel set rel_status=?,
                 rel_active='f' where rel=?";
      my $sth2 = $Para::dbh->prepare_cached( $st2 );
      $sth2->execute( S_DENIED, $tid );
  }

    ### t.t_entry_parent
  {
      my $childlist = $t->childs;

      my $next = $t->next;

      foreach my $entry ( @$childlist )
      {
	  die "not implemented";
#	  $t->delete_cascade;
      }

      if( $next )
      {
	  die "not implemented";
#	  $next->delete_cascade;
      }
  }

    ### ts
  {
      my $st1 = "update ts set ts_status=?,
                 ts_active='f' where ts_entry=? and ts_active is true";
      my $sth1 = $Para::dbh->prepare_cached( $st1 );
      $sth1->execute( S_DENIED, $tid );

      my $st2 = "update ts set ts_status=?,
                 ts_active='f' where ts_topic=? and ts_active is true";
      my $sth2 = $Para::dbh->prepare_cached( $st2 );
      $sth2->execute( S_DENIED, $tid );
  }

    $t->remove_page;

    $t->changed_all_versions;
}

sub mark_publish
{
    my( $t ) = @_;

    unless( $ENV{MOD_PERL} )
    {
	return $t->mark_publish_now;
    }

    my $tid = $Para::query->param('tid');
    if( $tid and $tid == $t->id )
    {
	$t->mark_publish_now;
    }
    else
    {
	$Para::Topic::to_publish->{$t->id} = $t->id;
    }
}

sub mark_publish_now
{
    my( $t ) = @_;

    if( $t->topic )
    {
	$t = $t->topic;
    }

    $Para::Topic::to_publish_now->{$t->id} = $t;
}

sub mark_unpublished
{
    my( $t ) = @_;

    unless( $t->entry )
    {
	# This way is maby a litle faster...
	$t->mark_publish;

#	my $sth = $Para::dbh->prepare_cached("update t set t_published='f' where t=? and t_ver=?");
#	$sth->execute($t->id, $t->ver);
    }

    if( my $top = $t->topic )
    {
	$top->mark_unpublished;
    }
}

sub mark_unsaved
{
    my( $t ) = @_;

    my $tid = $t->id;
    my $v = $t->ver;

    $Para::Topic::UNSAVED{"$tid-$v"} = $t;
}

sub save
{
    my( $t ) = @_;

    my $tid = $t->id;
    my $v   = $t->ver;

    my( @fields, @values );

    my $saved = $t->_new( $tid, $v, 1); # Nocache

    my @fields_to_check = qw( t_pop t_size t_title
			      t_title_short t_title_short_plural
			      t_text t_comment_admin t_file t_oldfile
			      t_urlpart t_class t_entry t_entry_parent
			      t_entry_next t_entry_imported
			      t_connected t_connected_status
			      t_replace);

    foreach my $key ( @fields_to_check )
    {
	if( ($t->{ $key }||'') ne ($saved->{ $key }||'') )
	{
	    push @fields, $key;
	    push @values, $t->{ $key };
	    warn "$$: field $key differ\n";
	}
    }

    if( @fields )
    {
	# Update changedby. Timestamp set in the statement
	push @fields, 't_changedby';
	push @values, $Para::Frame::U->id;

	# Update topic
	my $statement = "update t set ". join( ', ', map("$_=?", @fields)) .
	    ", t_updated=now() where t=? and t_ver=?";
	my $sth = $Para::dbh->prepare_cached( $statement );
#	warn "Running $statement\n";
	$sth->execute( @values, $tid, $v );

	$t->{'updated'} = now();
	$t->{'t_updated'} = $t->{'updated'}->cdate;

	$t->mark_publish;
    }

    delete $Para::Topic::UNSAVED{"$tid-$v"};

    return scalar @fields; # The number of changes
}

sub vacuum
{
    my( $t, $seen, $args ) = @_;

    debug(1,sprintf "Vacuum %d v%d", $t->id, $t->ver);
    $args ||= {}; # one_version
    $seen ||= {};
    return if $seen->{ $t->key };
    $seen->{ $t->key } = $t; # Does this exclude topics?!?

    # Vacuum all other versions
    #
    unless( $args->{'one_version'} )
    {
	foreach my $v ( reverse @{$t->versions} )
	{
	    next if $v->ver == $t->ver;

	    $v->vacuum( $seen, {one_version=>1} );
	}

	### Add top t_entry_imported, as a vaccum counter
	#
	my $st = "update t set t_entry_imported=t_entry_imported+1 where t=? and t_ver=?";
#	warn sprintf "Execute $st (%d, %d)\n", $t->id, $t->ver;
	my $sth = $Para::dbh->prepare_cached( $st );
	$sth->execute( $t->id, $t->ver );
    }

    # Break loops
    #
    $t->maby_loopy(1);
    $t->break_entry_loop;

    # Vacuum relations
    #
    unless( $args->{'one_version'} )
    {
	# Break loops
	#
	$t->break_topic_loop;

	# Fix errors inside  specific arcs
	#
	my $rel_arc_list = $t->rel->arcs;
	my $rev_arc_list = $t->rev->arcs;
	foreach my $arc ( @$rel_arc_list, @$rev_arc_list )
	{
	    $arc->vacuum( $seen );
	}

	# Remove duplicates
	my $mem = {};
	foreach my $arc (@{$t->arcs})
	{
	    my $key = $arc->obj ? $arc->obj->id : $arc->value;
	    my $rid = $arc->pred->id;
	    my $comment = $arc->comment || '-';
	    my $true = $arc->true;
	    my $sarc; #Surviving arc

	    if( my $arc2 = $mem->{ $key }{ $rid }{ $true }{ $comment } )
	    {
		warn "$$: Eliminating duplicate arc\n";
		if( $arc->active and $arc2->inactive )
		{
		    $arc2->remove;
		    $sarc = $arc;
		}
		elsif( $arc->inactive and $arc2->active )
		{
		    $arc->remove;
		}
		elsif( $arc->active and $arc2->active )
		{
		    $arc->remove('force')
		}
		elsif( $arc->created gt $arc2->created )
		{
		    $arc->remove;
		}
		else
		{
		    $arc2->remove;
		    $sarc = $arc;
		}
	    }
	    else
	    {
		$sarc = $arc;
	    }
	    $mem->{ $key }{ $rid }{ $true }{ $comment } = $sarc if $sarc;
	}

	# Fix worng status in arcs
	foreach my $arc (@{$t->arcs})
	{
	    $arc->vacuum( $seen );
	}

	# Find multipredtype topicrelations
	# TODO !!!

	# Add aliases
	$t->title2aliases( $t->title );
	$t->title2aliases( $t->real_short );
	$t->title2aliases( $t->real_plural );
	$t->generate_url;
    }

    unless( $args->{'one_version'} )
    {
	# Max one active version
	#
	my $active_ver;
	if( $t->active )
	{
	    $active_ver = $t->ver;
	}
	# Starts with latest version (prefered)
	foreach my $v ( reverse @{$t->versions} )
	{
	    if( $v->active )
	    {
		if( $active_ver )
		{
		    if( $active_ver != $v->ver )
		    {
			$v->set_status( S_REPLACED, -1 );
		    }
		}
		else
		{
		    $active_ver = $v->ver;
		}
	    }
	    else
	    {
		# Make sure status is right value
		if( $v->status >= S_PENDING )
		{
		    $v->set_status( S_REPLACED, -1 );
		}
	    }
	}

	if( $active_ver )
	{
	    # Active version should have the right status
	    my $t_a = Para::Topic->get_by_id( $t->id, $active_ver );
	    if( $t_a->status < S_PROPOSED )
	    {
		$t_a->set_status( S_PROPOSED, -1 );
	    }
	}
    }

    # Vacuum entries
    #
    foreach my $e (@{ $t->childs({include_inactive=>1}) })
    {
	$e->vacuum( $seen );
    }
    if( my $e = $t->next )
    {
	$e->vacuum( $seen );
    }

    # Vacuum aliases
    #
    foreach my $a (values %{ $t->aliases } )
    {
	$a->vacuum;
    }

    return $t;
}

sub set_class_flag
{
    my( $t, $flag ) = @_;

    $flag = $flag ? 1 : 0;

    if( $t->class xor $flag )
    {
	$t->{'t_class'} = $flag;
	$t->mark_unsaved;
    }
}

sub set_oldfile
{
    my( $t, $file ) = @_;

    if( $t->oldfile ne $file )
    {
	$t->{'t_oldfile'} = $file;
	$t->mark_unsaved;
    }
}

sub equals
{
    my( $t1, $t2 ) = @_;

    return undef unless ref $t2;
    if( $t1->id == $t2->id )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub generate_url
{
    my( $t, $exception ) = @_;

    debug(1,sprintf "Generating url for %s", $t->sysdesig);

    # Supported old calling with tid
    $t = Para::Topic->get_by_id( $t ) unless ref $t eq 'Para::Topic';

    $exception ||= {};
    my @handled = ();

    if( $t->entry )
    {
	if( my $top = $t->topic ) # Belongs to topic?
	{
	    my $page_url = $top->file;
	    my $entry_id = $t->id;
	    my $url = "$page_url#$entry_id";

	    debug(1,"$entry_id  $url");
	    $t->file( $url );
	    return [$entry_id];
	}
	debug(1,"*** entry $t->{t} has no topic");
	return []; # Rouge entry
    }

    # Some things should not have URLs. Such as anonymous users
    #
    if( my $m = $t->member )
    {
	if( $m->present_contact_public < 5 )
	{
	    $t->file(''); # This will make filename undef
	    debug(1,sprintf "%s is a anonumous user", $m->desig);
	    return [];
	}

	if( $m->level < 0 )
	{
	    $t->file(''); # This will make filename undef
	    debug(1,sprintf "%s is an old user", $m->desig);
	    return [];
	}
    }



    # Make up a list of all topics with the same title
    #
    my $alts = {};
    foreach my $rec ( @{$Para::dbix->select_list("from t where t_active is true and t_urlpart = ? and t_entry is false", title2url( $t->title )) } )
    {
	debug(1,"Found topic $rec->{t} with this title");
	my $prop = {};
	foreach my $rel ( @{$Para::dbix->select_list("from rel where rev=? and rel_type<4 and rel_type>0 and rel_active is true and rel_status >= ? and rel_strength >= ?", $rec->{'t'}, S_NORMAL, TRUE_MIN)} )
	{
	    $rel->{'rel'} or next;
	    # Lower cnt is less connected and thus higher in the heiarchy
	    my $wrec = $Para::dbix->select_record("select count(rev)+1 as cnt from rel where rev=? and rel_active is true and rel_status >= ? and rel_strength >= ?", $rel->{'rel'}, S_NORMAL, TRUE_MIN);

	    $prop->{$rel->{'rel'}} = $wrec->{'cnt'}||1;
	}
	$alts->{$rec->{'t'}}{'primary'} = $prop;
    }

    my @altkeys = keys %$alts;

    debug(1,sprintf "  Got %d altkeys\n", scalar(@altkeys));
    return [$t->id] unless @altkeys;


    # Remove non unique props
    foreach my $alt ( @altkeys )
    {
	foreach my $oalt ( @altkeys )
	{
	    next if $alt == $oalt;

	    foreach my $prop ( keys %{$alts->{$alt}{'primary'}} )
	    {
		if( $alts->{$oalt}{'primary'}{$prop} )
		{
		    $alts->{$alt}{'secondary'}{$prop} = $alts->{$alt}{'primary'}{$prop};
		    $alts->{$oalt}{'secondary'}{$prop} = $alts->{$oalt}{'primary'}{$prop};
		    delete $alts->{$alt}{'primary'}{$prop};
		    delete $alts->{$oalt}{'primary'}{$prop};
		}
	    }
	}
    }

    # Assign URL to topic
    my $url = "";
    if( @altkeys > 1 )
    {
	foreach my $alt ( @altkeys )
	{
	    next if $exception->{$alt};

	    #Use the most general alternative
	    my $prophash = $alts->{$alt}{'primary'};
	    my @props = sort{ $prophash->{$a} <=> $prophash->{$b} } keys %{$prophash};

	    if( @props )
	    {
		my $prop = $props[-1];

		my $prop_rec = $Para::dbix->select_record("from t where t_active is true and t=?", $prop);
		my $alt_rec = $Para::dbix->select_record("from t where t_active is true and t=?", $alt);
		my $prop_part = title2url( $prop_rec->{'t_title'} );
		my $alt_part = title2url( $alt_rec->{'t_title'} );
		$url = "/$prop_part/$alt_part";
	    }
	    else
	    {
		$prophash = $alts->{$alt}{'secondary'};
		@props = sort{ $prophash->{$a} <=> $prophash->{$b} } keys %{$prophash};

		my $alt_rec = $Para::dbix->select_record("from t where t_active is true and t=?", $alt);
		my $alt_part = title2url( $alt_rec->{'t_title'} );

		if( @props )
		{
		    my $prop = $props[-1];

		    my $prop_rec = $Para::dbix->select_record("from t where t_active is true and t=?", $prop);
		    my $prop_part = title2url( $prop_rec->{'t_title'} );
		    $url = "/$prop_part/$alt_part/$alt_rec->{'t'}";
		}
		else
		{
		    $url = "/$alt_part/$alt_rec->{'t'}";
		    debug(1,"Can't find deliminating prop for $alt\n".Dumper($alts));
		}
	    }

	    $url = "/topic$url.html";
	    debug(1,"$alt  $url");

	    Para::Topic->get_by_id( $alt )->file( $url );

	    push @handled, $alt;
	}
    }
    elsif( @altkeys )
    {
	my $alt = $altkeys[0];
	return([]) if $exception->{$alt};

	my $alt_rec = $Para::dbix->select_record("from t where t_active is true and t=?", $alt);
	my $alt_part = title2url( $alt_rec->{'t_title'} );
	$url = "/topic/$alt_part.html";
	debug(1,"$alt  $url");
	Para::Topic->get_by_id( $alt )->file( $url );

	push @handled, $alt;
    }
    else
    {
	debug(1,"No altkeys for ".Dumper($t));
    }

    return(\@handled);
}

sub publish_lock
{
    my $lock = new IO::LockedFile( { block => 0 }, PUBLISH_LOCK, '>' );
    $lock and $lock->print($$);
    return $lock;
}

sub publish
{
    my( $t ) = @_;

    use File::Path;

    $t = Para::Topic->get_by_id( $t ) unless ref $t eq 'Para::Topic';
    $t = $t->topic if $t->entry;
    return undef unless $t;

    my $tid = $t->id;

    debug(1,"Publish tid $tid");

    if( $t->file ) # Will generate_url on demand
    {
   	my $params = $t->publish_params;
	$params->{'tid'} = $tid;
	$params->{'t'} = $t;

	my $docroot = $Para::Frame::CFG->{'approot'};
	my $template_base = $docroot."/inc/static/";
	my $template;
	if( $t->member and $t->member->id > 0 )
	{
	    $template='paranormalse';
	}
	unless( $template )
	{
	    foreach my $arc ( @{$t->arcs({pred=>[1,7], true=>1, active=>1})} )
	    {
		my $name = title2url( $arc->obj->title );
		debug(2,"Looking for $name template");
		if( -e $template_base . $name . ".tt" )
		{
		    $template = $name;
		}
	    }
	}

	$template ||= "default";
	debug(1,"Using template $template");


	# Is this a mass member topic?
	#
	my $multi;
      MULTISELECT:
	{
	    $multi = $t->rev({type => 7})->topics;
	    if( @$multi > 20 )
	    {
		$params->{'multi'} = 'rev_7';
		$params->{'multi_sub'} = 'rev_29'; # har medlemskap
		$params->{'multi_plural'} = "medlemmar";
		last;
	    }

	    $multi = $t->rev({type => 1})->topics;
	    if( @$multi > 20 )
	    {
		$params->{'multi'} = 'rev_1';
		$params->{'multi_sub'} = 'rev_2'; # innefattar
		my $plural = $t->plural;
		$params->{'multi_plural'} = "\L$plural";
		last;
	    }

	    $multi = [ map $_->entry, @{$t->ts_revlist} ];
	    if( @$multi > 50 )
	    {
		$params->{'multi'} = 'rev_ts';
		$params->{'multi_plural'} = "media";
		last;
	    }
	}

	# Diffrent formats for diffrent sizes...
	my $cnt = @$multi;
	$params->{'multi_cnt'} = $cnt;

	if( $cnt > 2000 )
	{
	    # Too many to list
	}
	elsif($params->{'multi'})
	{
	    my %content; # $content{'a'} = [@sorted_content]

	    foreach my $mt ( @$multi )
	    {
		next unless $mt->file;

		foreach my $alias (@{ $mt->alias_list })
		{
		    next unless $alias->index;

		    my $letter;
		    my $name = lc( $alias->name );

		    my $first = substr( $name, 0, 1);
		    if( $first =~ /^[a-zåäö]$/i )
		    {
			$letter = $first;
		    }
		    else
		    {
			$letter = '-';
		    }

		    $content{$letter} ||= [];
		    push @{$content{$letter}}, [ $name, $mt ];
		    debug(3,"Inserting $mt to content of $letter");
		}
	    }

	    my $urldir = $t->{'t_file'};
	    $urldir =~ s/\.html$//;
	    $params->{'multi_dir'} = $urldir;

	    my $letters = ['-','a'..'z','å','ä','ö'];

	    if( $cnt < 200 )
	    {
		my $newletters = ['-'];
		my $last = 'a';
		foreach my $i (1..$#$letters)
		{
		    if( not $i % 6 )
		    {
			my $part = $last.'-'.$letters->[$i-1];
			push @$newletters, $part;
			$content{$part} = $content{$last};
			debug(2,"Associate the content of $last to $part");
			$last = $letters->[$i];
		    }

		    my $this = $letters->[$i];
		    $content{$this} ||=[];
		    unless( $this eq $last )
		    {
			push @{$content{$last}}, @{$content{$this}};
		    }
		}
		my $part = $last.'-'.$letters->[$#$letters];
		push @$newletters, $part;
		$content{$part} = $content{$last};
		debug(2,"Associate the content of $last to $part");

		$letters = $newletters;
		$params->{'multi_separator'} = ' | ';
	    }

	    $params->{'multi_letters'} = $letters;
	    $params->{'multi_content'} = [];
	    foreach my $letter ( @$letters )
	    {
		debug(1,"Letter $letter");
		$params->{'multi_letter'} = $letter;
		$content{$letter} ||=[];
		debug(3,"Content: @{$content{$letter}}");
		@{$params->{'multi_content'}} =
		    sort {$a->[0] cmp $b->[0] } @{$content{$letter}};

		

		my $file = "$urldir/$letter.html";
		$t->write_page('multi', $params, $file);
	    }
	    undef $params->{'multi_letter'};
	    undef $params->{'multi_content'};
	}

	$t->write_page( $template, $params );
    }
    else
    {
	debug(1,"  Topic $tid has no URL");
    }

    return $t->set_published;
}

sub published
{
    my( $t ) = @_;

    return $t->{'t_published'};
}

sub write_page
{
    my($t, $template, $params, $file) = @_;

    $file ||= $t->{'t_file'};
    $params ||= $t->publish_params;

    local $Para::state = 'static';

    # Become unpriviliged user
    $Para::Frame::REQ->{'real_user'} = $Para::Frame::U;
    my $john_doe = Para::Member->get( 46 );
    $Para::Frame::U->change_current_user( $john_doe );

    my $approot = $Para::Frame::CFG->{'approot'};
    my $pfroot  = $Para::Frame::CFG->{'paraframe'};

    my @incpath = "$approot/inc/static/$template";
    unless( $template eq 'default' )
    {
	push @incpath, "$approot/inc/static/default";
    }
    push @incpath, "$approot/inc", "$pfroot/inc";

    my $th = Template::Context->new
	(
	 INTERPOLATE  => 1,
	 INCLUDE_PATH => \@incpath,
	 COMPILE_DIR  =>  '/var/local/paranormal/ttc/psidb2',
	 COMPILE_EXT  => '.ttc',
	 PRE_CHOMP    => 0,
	 POST_CHOMP   => 0,
	 TRIM         => 1,
	 EVAL_PERL    => 0,
	 FILTERS      =>
	 {
	     'uri' => sub { CGI::escape($_[0]) },
	     'html_psi' => \&Para::Widget::html_psi,
	 }
	 );

    my $template_file = "static/$template.tt";

    eval
    {
	my $page = $th->process($template_file, $params);
 
	my $sysfile = sysfile( $file );

	my $dir = $sysfile; $dir =~ s/\/[^\/]+$//g;
	mkpath( $dir );

#    warn "--> Publishing to $sysfile using $template\n";
	open PAGE, ">$sysfile"
	    or die "Kunde inte skriva till $sysfile: $!";
	print PAGE $page;
	close PAGE;
    };
    if( $@ )
    {
	my $req = $Para::Frame::REQ;
	$req->result->message("Fel uppstod när vi försökte skapa\n$file\nmed hjälp av $template_file");
    }


    # Return to original user
    $Para::Frame::U->revert_from_temporary_identity;

    die $@ if $@; # Forward exception

    return 1;
}

sub publish_params
{
    my( $t, $extra ) = @_;

    my $params = clone($Para::Frame::PARAMS);

    $params->{'site'} = $Para::Frame::CFG->{'site'};
    $params->{'home'} = $Para::Frame::CFG->{'site'}{'webhome'};
    return $params;
}

sub remove_page
{
    my( $t ) = @_;

    my $file = $t->{'t_file'} or return;

    my $sysfile = sysfile( $file );

    if( -e $sysfile )
    {
#	warn "$$: Removing file $sysfile\n";  ### DEBUG
	unlink $sysfile or die $!;
    }
}

sub set_published
{
    my( $t, $sth ) = @_;

    my $sth ||= $Para::dbh->prepare_cached("update t set t_published='t' where t=?");

    # Och publicera nu alla aktiva barn
    #
    foreach my $child ( @{$t->childs} )
    {
	$child->set_published($sth);
    }

    if( $t->next )
    {
	$t->next->set_published($sth);
    }

    $sth->execute($t->id);
}

sub type_list
{
    my( $t ) = @_;

    my $rel = $t->id;

    my @reltypes = (1, 2);
    my @exclude  = (1, 10, 11, 12, 2910);

    my $reltypes = join ', ', @reltypes;
    my $exclude = join ', ', @exclude;

    my $list = $Para::dbix->select_list("select t from rel, t
                            where rel_active is true
                            and t_active is true
                            and rev=? and rel_type in ($reltypes)
                            and rel=t and rel_indirect is false
                            and rel_strength >= 30
                            and t not in ($exclude)", $rel );
#    warn "returnted @$list";
    return [ map Para::Topic->get_by_id( $_->{t} ), @$list ];
}

sub type_list_string
{
    my( $t ) = @_;

    my $listref = $t->type_list;
    return "" unless @$listref;
    my $res = '<span class="typelist">';
#    warn @$listref;
    $res .= join ", ", map $_->title, @$listref;
    $res .= '</span>';
    return $res;
}




############### Utility functions

sub title2url
{
    my( $title ) = @_;

    deunicode( $title );

    my $url = lc($title);

    $url =~ tr[àáâäãåæéèêëíìïîóòöôõøúùüûýÿ]
	      [aaaaaaaeeeeiiiioooooouuuuyy];
    $url =~ s/[^\w\s-]//g;
    $url =~ s/\s+/_/g;
    $url =~ s/( ^_+ | _+$ )//gx;
    return $url;
}

sub sysfile
{
    my( $file ) = @_;

    my $docroot = $Para::Frame::CFG->{'approot'};
    my $topicdir = $docroot."/topic/";
    my $sysfile = $docroot.$file;

    $sysfile =~ s!^($topicdir)(([^/\.][^/\.]).+)!$1$3/$2!o;

    return $sysfile;
}



####################################### END

1;
