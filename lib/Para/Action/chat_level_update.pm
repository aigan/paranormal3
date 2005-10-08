#  $Id$  -*-perl-*-
package Para::Action::chat_level_update;

use strict;
use Data::Dumper;
use List::Util qw( min );

use Para::Frame::Utils qw( throw );

use Para::Member;
use Para::Constants qw( C_OP );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->chat_level < C_OP )
    {
	throw('denied', "Endast för ops");
    }



    foreach my $param ( $q->param )
    {
#	warn "checking $param\n";
	next unless $param =~ /^chat_level-(.*)/;
	my $mid = $1;
	my $member = Para::Member->get( $mid );
	my $level = $q->param( $param );
	if( $level != $member->chat_level )
	{
	    next if $u->chat_level < $member->chat_level;
	    $level = min(  $u->chat_level, $level );
#	    warn "about to set chat_level $level for $mid\n";
	    $member->set_field_number('chat_level', $level);
	}
    }

    if( my $new = $q->param('new') )
    {
	my $member = Para::Member->get_by_nickname( $new );
	$member or throw('validate',"Hittar inte medlem $new");
	my $level = $q->param('chat_level');
	if( $level != $member->chat_level )
	{
	    next if $u->chat_level < $member->chat_level;
	    $level = min(  $u->chat_level, $level );
	    $member->set_field_number('chat_level', $level);
	}
	$q->delete('new');
    }

    return "Chat levels updated\n";
}

1;
