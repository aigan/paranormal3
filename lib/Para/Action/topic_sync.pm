#  $Id$  -*-perl-*-
package Para::Action::topic_sync;

use strict;
use Data::Dumper;
use File::Find;
use IO::LockedFile;

use Para::Frame::Utils qw( throw debug );
use Para::Frame::Time;

use Para::Topic;

use vars qw( $pcnt $rcnt $vcnt $base $afs );
use constant LIMIT => 300;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 12 )
    {
	throw('denied', "Enbart för väktare");
    }

    $pcnt = 0;
    $rcnt = 0;
    $base = uri2file('/');


    # Active files
    $afs = select_key('t_file', "select t, t_file, t_updated, t_title
                                 from t where t_active is true and
                                 t_entry is false and t_file is not null
                                ") or die;



    debug "===> Publishing changed pages\n";
    #
    foreach my $af ( keys %$afs )
    {
	my $rec = $afs->{$af};

	my $tid = $rec->{'t'};
	my $file = $base.$rec->{'t_file'};
	$file =~ s!^($base/topic/)(([^/\.][^/\.]).+)!$1$3/$2!;

	my $title = $rec->{'t_title'} or die;
	my $warn = "\nCheck $title\n";

	if( my $fh = new IO::File $file )
	{
	    my $st = stat($fh) or next;
	    my $published = $st->mtime;
	    my $updated = Para::Frame::Time->get($rec->{'t_updated'})->epoch;

	    if( $published >= $updated )
	    {
		debug "$warn  Redan publicerad\n";
		next;
	    }
#	    warn "$warn  Uppdaterad sida\n";

	    debug "-------------------------\n";
	    debug "Found an unpublished page\n";
	    debug "File: $file\n";
	    debug "\n";
	    debug sprintf "Published: %s\n", scalar localtime $published;
	    debug sprintf "Updated  : %s\n", scalar localtime $updated;
	    debug "\n";

	}
	else
	{
	    debug "$warn  Ej ännu publicerad\n";
	}

	my $t = Para::Topic->get_by_id( $tid );
	$t->publish;

	last if ++ $pcnt >= LIMIT;
    }

    debug "===> Removing nonactive topics\n";
    #
    debug  "Traversing $base/topic\n";
    find(\&wanted, "$base/topic");

    return "$pcnt sidor publicerade. $rcnt sidor raderade.\n";
}

sub wanted
{
    $File::Find::name =~ /^$base(.*)/;
    my $file = $1;

    return if -d  $File::Find::name;
    return if /^\./;
    return if /^index/;

    my $file2 = $file;
    # A nomatch is ok. Topics that are just one letter
    $file2 =~ s!^/topic/[^/][^/]/!/topic/!;

    # Is this a subpage? - should be one letter or start with '_'
    my $basefile = $file2;
    $basefile =~ s/\/([^\/]|[^\/]\-[^\/]|_[^\/]+)\.html$/.html/;

    if( $afs->{$basefile} )
    {
	# This was a subpage to active page
    }
    elsif( $afs->{$file} )
    {
	debug "File $file active\n";
    }
    elsif( $afs->{$file2} )
    {
	debug "File $file active\n";

	my $shortfile = $base . $file2;
	debug "Checking for $shortfile\n";
	if( -e $shortfile )
	{
	    debug "File $shortfile <--- SHOULD BE REMOVED\n";
	    debug "Removing file $file2\n";
	    unlink $shortfile;
	    $rcnt ++;
	}
    }
    else
    {
	debug "  Basefile is $basefile\n";
    	debug "File $file <--- SHOULD BE REMOVED\n";

	debug "Removing file $file\n";
	unlink $File::Find::name;
	$rcnt ++;
    }
}

1;
