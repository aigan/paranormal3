#  $Id$  -*-perl-*-
package Para::Action::topic_update;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw trim debug );
use Para::Frame::Change;

use Para::Constants qw( S_PROPOSED S_PENDING );
use Para::Utils qw( trim_text );
use Para::Topic qw( title2url );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 5 )
    {
	throw('denied', "Du måste bli medborgare för att få uppdatera ett ämne");
    }

    # Remove stored DB params so that the value in the html form
    # reflects the new value
    #
    @Para::clear_fields = ();

    my $tid = $q->param('tid')
	or throw('incomplete', "tid param missing\n");
    my $ver = $q->param('v');

    my $t = Para::Topic->get_by_id( $tid, $ver )
	or throw('validation', "Can't find topic $tid v$ver");
    $ver ||= $t->ver;

    # Create a changes obj
    my $changes = $req->change;


    Para::History->begin();

    debug "Checking $tid v$ver";

    check_talias_edit($t);
    check_rel_edit($t);
    check_rel_create($t);
    check_status($t);
    check_text_edit($t);
    check_class($t);
    check_oldfile($t);
    check_media($t);


    $u->interest( $t ); # Mark interest

    # Clear fields used for adding new things
    foreach my $thing ( @Para::clear_fields )
    {
	$q->delete($thing);
    }


    $q->param('tid', $tid);
#    $q->param('step_replace_params', 'tid'); #use new tid

#    $changes->success("De nya uppgifterna har sparats");
    $changes->report;
}

sub check_class
{
    my( $t ) = @_;

    return unless $Para::Frame::U->level >= 40;
    my $q = $Para::Frame::REQ->q;

    if( $q->param('_meta_class') )
    {
	if( $q->param('t_class') )
	{
	    $t->set_class_flag(1);
	}
	else
	{
	    $t->set_class_flag(0);
	}
	push @Para::clear_fields, '_meta_class', 't_class';
    }
}

sub check_oldfile
{
    my( $t ) = @_;

    return unless $Para::Frame::U->level >= 11;

    my $q = $Para::Frame::REQ->q;

    if( my $file = $q->param('t_oldfile') )
    {
	$t->set_oldfile( $file );
	push @Para::clear_fields, 't_oldfile';
    }
}

sub check_talias_edit
{
    my( $t ) = @_;
    ### _talias__ edit  ( the KEY is talias )

    my $m = $Para::Frame::U;
    my $q = $Para::Frame::REQ->q;

    for( my $row=1; defined(my $talias = $q->param("_talias__${row}_talias")); $row++ )
    {
	debug "Checking $row, $talias";
	push @Para::clear_fields, "_talias__${row}_talias", "_talias__${row}_keep", "_talias__${row}_activate", "_talias__${row}_talias_autolink", "_talias__${row}_talias_index", "_talias__${row}_talias_language";

	my $a = $t->alias($talias) or
	  die sprintf "Can't find alias '$talias' for %s\n", $t->desig;

	if( $q->param("_talias__${row}_activate") )
	{
	    $q->param("_talias__${row}_keep", 1);
	    $a->activate;
	    warn "  activated\n";
	}

	my $active;
	if( $q->param("_talias__${row}_keep") )
	{
	    $active = 1;
	}
	else
	{
	    $active = 0;
	}

	next unless $active or $a->active; # Don't change inactive aliases

	my $autolink    = $q->param("_talias__${row}_talias_autolink") || 0;
	my $index       = $q->param("_talias__${row}_talias_index") || 0;
	my $language = $q->param("_talias__${row}_talias_language");

	$a->update({
		    autolink => $autolink,
		    index    => $index,
		    language => $language,
		    active   => $active,
		   });
    }

    if( my $val = $q->param('_meta_talias') )
    {
	warn "Found topicalias list\n";
	my $new = {};
	my $add = [];
	my $del = [];
	foreach my $row ( split /\n/, $val )
	{
	    trim(\$row);
	    next unless length($row);
	    # Normalize entry
	    $new->{lc($row)} ++;
	}
	# Add things

	foreach my $thing ( keys %$new )
	{
	    $t->add_alias( $thing );
	}
    }

}

sub check_rel_edit
{
    my( $t ) = @_;
    ### _rel__#_ edit  ( the KEY is rel_topic )  Edit EXISTING

    my $tid = $t->id;
    my $ver = $t->ver;
    my $q = $Para::Frame::REQ->q;

    my $rows = $q->param("_rel__rows") or return; # No rows count?
    push @Para::clear_fields, "_rel__rows";

    for( my $row=1; $row <= $rows; $row++ )
    {
	warn "check_rel_edit row $row\n";

	my $rel_topic = $q->param("_rel__${row}_rel_topic");
	unless( $rel_topic )
	{
	    warn "  topic empty for row!\n";
	    return;
	}
	my $rel_keep  = $q->param("_rel__${row}_keep")     ? 1 : 0;
	my $rel_true  = $q->param("_rel__${row}_true")     ? 1 : 0;
	my $rel_value = $q->param("_rel__${row}_rel_value");
	my $rel_origdir = $q->param("_rel__${row}_rel_origdir");

	my($rel_type, $rel_dir) = $q->param("_rel__${row}_type") =~
	    /^(\d+)+_(rev|rel)$/ or die "malformed _rel__${row}_type\n";

	push( @Para::clear_fields,
	      "_rel__${row}_rel_topic",
	      "_rel__${row}_keep",
	      "_rel__${row}_true",
	      "_rel__${row}_type",
	      "_rel__${row}_rel_value",
	      "_rel__${row}_rel_origdir",
	      );

	my $arc = Para::Arc->get($rel_topic);
	my $new_props =
	{
	 comment => $arc->comment,
	 true    => $rel_true,
	 active  => $rel_keep,
	};

	if( $rel_type != $arc->type->id or $rel_dir ne $rel_origdir )
	{
	    if( $rel_dir eq $rel_origdir )
	    {
		$arc = $arc->replace( $rel_type, $arc->subj, $arc->obj,
				      $new_props );
	    }
	    else
	    {
		$arc = $arc->replace( $rel_type, $arc->obj, $arc->subj,
				      $new_props );
	    }
	}

	if( defined $rel_value and $rel_value ne $arc->value )
	{
	    $arc = $arc->replace( $arc->pred, $arc->subj, $rel_value,
				  $new_props );
	}

	if( $rel_keep xor $arc->active ) ## Activation changed?
	{
	    if( $rel_keep )
	    {
		$arc->activate;
	    }
	    else
	    {
		$arc->deactivate;
	    }
	}
	elsif( $rel_true xor $arc->true )
	{
	    $arc->replace( $arc->pred, $arc->subj, $arc->obj,
			      $new_props );
	}
    }
}

sub check_rel_create
{
    my( $t ) = @_;
    ### _rel__n_ edit  ( the KEY is rel_topic )  Add NEW

    my $tid = $t->id;
    my $ver = $t->ver;
    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $site = $req->site;

    foreach my $row (1..5)
    {
	push @Para::clear_fields, "_rel__n_${row}_rel_type", "_rel__n_${row}_rel", "_rel__n_${row}_rel_comment";
	my $reltype_name = $q->param("_rel__n_${row}_rel_type");
	my $rel_name = $q->param("_rel__n_${row}_rel");
	my $rel_comment = $q->param("_rel__n_${row}_rel_comment");

	trim(\$reltype_name);
	trim(\$rel_name);
	trim(\$rel_comment);

	if( defined $reltype_name and $rel_name )
	{
	    eval
	    {
		Para::Arc->create( $reltype_name,
				  $t,
				  $rel_name,
				{
				 comment => $rel_comment,
				 active => 1,
				},
				);
	    };
	    if( $@ )
	    {
		if( ref $@ and $@->[0] eq 'alternatives' )
		{
		    my $res = $req->result;
		    $res->{'info'}{'alternatives'}{'replace'} = "_rel__n_${row}_rel";
		    $res->{'info'}{'alternatives'}{'view'} = "/member/db/topic/edit/meta.tt";

		    $req->set_error_template($site->home.'/alternatives.tt');
		    $req->s->route->bookmark;
		}
		die $@; # Propagate error
	    }
	    push @Para::clear_fields, "_rel__n_${row}_rel_type", "_rel__n_${row}_rel", "_rel__n_${row}_rel_comment";
	}
    }
}

sub check_text_edit
{
    my( $t ) = @_;
    ### Check text and title

    my $tid = $t->id;
    my $ver = $t->ver;
    my $req = $Para::Frame::REQ;
    my $q = $req->q;


#    my $status = level2status($Para::Frame::U->level, 1);
    my $u = $Para::Frame::U;

    my $old_text = $t->text || '';
    trim_text( \$old_text );
    my $new_text = $q->param('t_text') || $old_text;
    trim_text( \$new_text );

    my $old_comment_admin = $t->admin_comment || '';
    trim( \$old_comment_admin );
    my $new_comment_admin = $q->param('t_comment_admin');
    $new_comment_admin = $old_comment_admin unless defined $new_comment_admin;
    trim( \$new_comment_admin );

    my $old_title = $t->title || '';
    trim( \$old_title );
    my $new_title = $q->param('t_title');
    $new_title = $old_title unless defined $new_title;
    trim( \$new_title );

    my $old_title_short = $t->real_short || '';
    trim( \$old_title_short );
    my $new_title_short = $q->param('t_title_short');
    $new_title_short = $old_title_short unless defined $new_title_short;
    trim( \$new_title_short );

    my $old_title_short_plural = $t->real_plural || '';
    trim( \$old_title_short_plural );
    my $new_title_short_plural = $q->param('t_title_short_plural');
    $new_title_short_plural = $old_title_short_plural
	unless defined $new_title_short_plural;
    trim( \$new_title_short_plural );

    push @Para::clear_fields, qw( t_text t_comment_admin t_title
				 t_title_short t_title_short_plural );


    if( $old_text ne $new_text or
	$old_comment_admin ne $new_comment_admin or
	$old_title ne $new_title or
	$old_title_short ne $new_title_short or
	$old_title_short_plural ne $new_title_short_plural
	)
    {
	unless( $t->active )
	{
	    warn "
Text: $old_text
      $new_text
Comment: $old_comment_admin
         $new_comment_admin
Title: $old_title
       $new_title
Title_short: $old_title_short
             $new_title_short
Title_short_plural: $old_title_short_plural
                    $new_title_short_plural
";
	    throw('validation',"Aktivera texten innan du ändrar i den");
	}

	$new_title = ucfirst( $new_title );

#	my $old_status = $t->status || 2;
#	my $new_status = level2status($Para::Frame::U->level);
#	my $new_active = 't';


	my $rec =
	{
	    title => $new_title,
	    short => $new_title_short,
	    plural => $new_title_short_plural,
	    text => $new_text,
	    admin_comment => $new_comment_admin,
	    url => title2url( $new_title ),
	};

	$t = $t->create_new_version($rec);


	$u->score_change('entry_submitted', 1);


	if( $t->status == S_PROPOSED )
	{
	    $req->change->note("Den nya versionen väntar på godkännande");
	}
	elsif( $t->status == S_PENDING )
	{
	    $req->change->note("Ändringen kommer att kontrolleras\n");
	}

	# Focus on new version
	$q->param('v', $t->ver);
    }
}

sub check_status
{
    my( $t ) = @_;

    my $tid = $t->id;
    my $ver = $t->ver;
    my $m = $Para::Frame::U;
    my $q = $Para::Frame::REQ->q;

    my $new_status = $q->param('t_status');
    return unless defined $new_status;
    return if $new_status eq '';

    if( $m->status < S_PENDING )
    {
	throw('denied', "Du kan inte ändra status på en text\n");
    }

    if( $new_status > $m->status )
    {
	throw('denied', "Reserverat för mästare\n");
    }

    $t->set_status( $new_status );

    push @Para::clear_fields, 't_status';
}

sub check_media
{
    my( $t ) = @_;

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $c = $req->change;

    my $url = $q->param('media_url');
    my $mime = $q->param('media_mimetype');

    return unless defined $url and defined $mime;

    # Change to the active version of the topic
    $t = $t->active_ver;
    unless( $t )
    {
	throw('validation', "Ämnet har inte en aktiv version");
    }

    if( $mime eq '' and $url eq '' )
    {
	$t->media_remove() and
	    $c->note("Raderade mediareferens");
    }
    elsif( $mime and $url )
    {
	$t->media_set( $url, $mime ) and
	    $c->note("Uppdaterar mediareferens");
    }
    else
    {
	$c->note("Definiera både url och mime för att ändra mediareferens");
    }
    return;
}

1;
