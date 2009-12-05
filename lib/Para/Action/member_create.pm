# -*-cperl-*-
package Para::Action::member_create;

use strict;

use Para::Frame::Utils qw( throw debug );

use Para::Member;

sub handler
{
    my( $req ) = @_;

    my $msg = "";

    my $q = $req->q;

    # Validating nick format
    #
    my $name = $q->param('nick');
    my $name_orig = $name;
    Para::Member::trim_name(\$name);

    my $nick = Para::Member::name2nick($name);
    my $chat_nick = Para::Member::name2chat_nick($name);

    Para::Member->validate_nick( $nick ); # Validate before the below tests

    if( $name_orig ne $name )
    {
	$q->param('nick', $name);
	throw('confirm',"Ditt namn har anpassats till våra regler.\nVill du använda detta namn?");
    }

    if( $chat_nick ne $name and $chat_nick ne $q->param('confirmed_chat_nick')  )
    {
	$q->param('confirmed_chat_nick', $chat_nick);
	throw('confirm',"När du chattar kommer du att använda \"$chat_nick\" som namn.\nFortsätt, eller ändra ditt namn.");
    }


    eval
    {
	my $m = Para::Member->create( $name );

	if( my $remote = $ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'} )
	{
	    $m->add_host_pattern( $remote );
	}

	# Created by another user
	my $u = $req->s->u;
	if( $u->level > 10 )
	{
	    my $uname = $u->nickname;
	    $m->set_field('member_comment_admin', "Skapad av $uname\n");
	}


	$q->param('mid', $m->id);

	$Para::dbh->commit;
	return "Ny medlem registrerad";
    }
    or do
    {
	#PQresultStatus PQerrorMessage PGresult (Where is the error code docs?)
	if( $Para::dbh->errstr =~ /nick_pkey/ )
	{
	    $Para::dbh->rollback;

	    debug "Kollar om nick $nick finns";
	    my $rec = $Para::dbix->select_record("from member, nick where member=nick_member and uid=?", $nick);
	    if( $rec->{'member_level'} > 1 )
	    {
		throw('validation', "Någon annan använder redan detta namn.  Välj ett annat\n");
	    }
	    else
	    {
		return "Påbörjad registrering återupptagen";
	    }
	}
	else
	{
	    die;
	}
    }
}

1;
