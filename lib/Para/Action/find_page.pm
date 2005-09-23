#  $Id$  -*-perl-*-
package Para::Action::find_page;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw deunicode catch uri2file debug );
use Para::Frame::DBIx;

use Para::Topic qw( title2url );

my $oldtypes =
{
    person    => 'person',
    group     => 'grupp',
    periodica => 'tidskrift',
    book      => 'bok',
};

my $oldchars =
{
    aa       => 'å',
    ae       => 'ä',
    oe       => 'ö',
};


sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;
    my $res = $req->result;

    my $uri = $ENV{'REDIRECT_SCRIPT_URI'} or
	throw('denied',"You should not be here!!!");

    my $host = $req->http_host;
    $uri =~ s/^https?:\/\/$host//;

    $uri =~ s/^\/topic\/(\w\w\/)/\/topic\//;
    debug "Prev URI: $uri";


    # Test many variants
    #
    # 0. Was this url unicoded?
    #
    # 1. lookup t_oldfile in t
    #
    # 2. If this is in one of the old sections we will try converting
    #    path to title
    #
    # 3. If this is one of the new sections, the section will be set.
    #    Mostly only handle the topic section
    #
    # 4. Other path parts is taken as qualifiers
    #
    # Try with and without oe => o conversions


    # Start by checking coding variants
    #
    if( $uri =~ /Ã/ )
    {
	$uri = deunicode( $uri );

	debug "Translating file to $uri";

	# Lookup corresponding filename
	my $filename = uri2file( $uri );
	if( -r $filename ) # Realy existing?
	{
	    $req->redirect($uri);
	    return "Redirecting";
	}
    }


    # oldfile ?
    #
    if( my $rec = $Para::dbix->select_possible_record("from t where t_oldfile=? and t_active is true and t_file is not null", $uri) )
    {
	my $newuri = $rec->{'t_file'};

	# Lookup corresponding filename
	my $filename =  uri2file( $newuri );
	if( -r $filename ) # Realy existing?
	{
	    $req->redirect( $newuri );
	    return "Redirecting";
	}
    }


    $uri =~ m!^(.*?)(?:\.(html|txt))?$! or die "That was strange";
    my $path = lc($1);
    my $format = $2;
    my $section = '';

    if( $path =~ m!^/([^/]+)/(.*?)$! )
    {
	$section = $1;
	$path    = $2;
    }

    my @possible = ();

    if( $section =~ /^(psi|person|group|periodica|book)$/ )
    {
	my $type = $oldtypes->{$section};

	# Special hndling of 'psi' section
	$type = 'psi' if $section eq 'psi';

	foreach my $variant ( variations_slash($path) )
	{
	    foreach my $subvariant ( variations_oe($variant) )
	    {
		push @possible, [ title2url($subvariant), $type ];
	    }
	}
    }
    else
    {
	my $type;
	if( $section =~ /^(topic|old)$/ )
	{
	    $section = 'topic';
	}
	else
	{
	    $type = $section;
	    $section = 'topic';
	}

	if( debug )
	{
	    debug "Path: $path";
	    debug "Section: $section";
	    debug "Type: $type" if $type;
	    debug "Format: $format";
	}

	if( $section eq 'topic' )
	{
	    my($first, $second, $rest) = split '/', $path, 3;

	    if( debug )
	    {
		debug "First: $first";
		debug "Second: $second" if $second;
		debug "Rest: $rest" if $rest;
	    }

	    if( $rest )
	    {
		$res->{'info'}{'notfound'}{'uri'} = deunicode($uri);
		my $name = url2title( $uri );
		$res->{'info'}{'notfound'}{'name'} = $name;
		throw('notfound', "Adressen är för lång för att vi ska kunna använda den för att hitta motsvarande ord i uppslagsverket.");
	    }
	    elsif( $second )
	    {
		$type = $first;
		$path = $second;
	    }

	    if( $second and $second =~ /^\d+$/ )
	    {
		debug "Lookig for tid $second";
		push @possible, [$second]; # The tid
	    }
	    else
	    {
		foreach my $variant ( variations_oe($path) )
		{
		    push @possible, [ title2url($variant), $type ];
		}
	    }
	}
	else
	{
	    throw('notfound',"");
	}
    }

    my %result;
    foreach my $choice ( @possible )
    {
	my $talias = $choice->[0];
	my $typename   = $choice->[1];

	if( debug )
	{
	    my $typenamestr = $typename ? " ($typename)" : "";
	    debug "Looking for $talias$typenamestr";
	}

	my $found;
	if( $talias =~ /^\d+$/ )
	{
	    $found = [Para::Topic->find_by_alias( $talias )];
	}
	else
	{
	    $found  = Para::Topic->find_urlpart( $talias );
	}

	debug "Found ".scalar(@$found)." matches";

	foreach my $t ( @$found )
	{
	    my( $title, $tid );
	    if( debug )
	    {
		$title = $t->title;
		$tid   = $t->id;
	    }

	    if( $typename and $typename eq 'psi' )
	    {
		debug"  $tid:$title in old Psi category?";
		my $clear = 1; #Not one of the specific types
		foreach $typename ( values %$oldtypes )
		{
		    $clear = 0 if $t->has_rel(1, $typename);
		}

		if( $clear ) # Old Psi category
		{
		    $result{$t->id} = $t;
		}
		else
		{
		    debug "    Other than psi category";
		}
	    }
	    elsif( $typename )
	    {
		debug "Checking if ".$t->sysdesig." has special relation to $typename";
		if( $t->has_rel([1,2,3,21,29,30,31,32], $typename) )
		{
		    $result{$t->id} = $t;
		    debug "  Yes";
		}
	    }
	    else
	    {
		$result{$t->id} = $t;
	    }
	}
    }

    my @topics = values %result;

    if( $topics[1] )
    {
	$res->{'info'}{'alternatives'}{'list'} = \@topics;
	my $euri = $q->escapeHTML( $uri );
	throw('alternatives', "Välj ett av dessa alternativ för <code>$euri</code>");
    }

    unless( $topics[0] )
    {
	debug "No topics found";
	$res->{'info'}{'notfound'}{'uri'} = deunicode($uri);

	my $name = url2title( $uri );
	$res->{'info'}{'notfound'}{'name'} = $name;
	$res->hide_part('notfound');

	throw('notfound',"");
    }

    my $t = $topics[0];

    my $newuri = $t->{'t_file'};

    unless( $newuri )
    {
	my $title = $t->desig;
	my $name = url2title( $uri );
	$res->{'info'}{'notfound'}{'name'} = $name;
	$res->{'info'}{'notfound'}{'tid'} = $t->id;
	$res->{'info'}{'notfound'}{'uri'} = "";
	throw('notfound', "Hittade $title, men det uppslagsordet är hemligt.");
    }

    # Lookup corresponding filename
    my $filename = uri2file( $newuri );
    debug "Trying $filename";
    if( -r $filename ) # Realy existing?
    {
	$req->redirect( $newuri );
    }
    else
    {
	# Try publish right now
	$t->publish;
	if( -r $filename ) # Exists now?!?
	{
	    $req->redirect( $newuri );
	}
	else
	{
	    my $name = url2title( $newuri );
	    $res->{'info'}{'notfound'}{'uri'} = $newuri;
	    $res->{'info'}{'notfound'}{'tid'} = $t->id;
	    $res->{'info'}{'notfound'}{'name'} = $name;
	    throw('notfound', "Den finns dock i databasen");
	}
    }

    return "What happend?";
}

sub variations_slash
{
    my( $path ) = @_;

    my @ver;

    # '/' => '' or ' '
    my($first, $rest) = split '/', $path, 2;
    if( $rest )
    {
	foreach my $variant ( variations_slash($rest) )
	{
	    push @ver, $first.' '.$variant;
	    push @ver, $first.''.$variant;
	}
    }
    else
    {
	push @ver, $path;
    }

    return @ver;
}

sub variations_oe
{
    my( $path ) = @_;

    my @ver;

    my($first, $char, $rest) = $path =~ /^(.*?)(aa|ae|oe)(.*)/;
    if( $char )
    {
	foreach my $variant ( variations_oe($rest) )
	{
	    push @ver, $first . $char . $variant;
	    push @ver, $first . $oldchars->{$char} . $variant;
	}
    }
    else
    {
	push @ver, $path;
    }

    return @ver;
}

sub url2title
{
    my( $url ) = @_;

    $url =~ /.*\/(.*?)(\.\w+)?$/;
    my $name = ucfirst($1);
    $name =~ s/_/ /g;

    deunicode( $name );

    return $name;
}

1;
