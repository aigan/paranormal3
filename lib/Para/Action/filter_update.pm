package Para::Action::filter_update;

use strict;

use Para::Frame::Time qw( date now );
use Para::Frame::Utils qw( throw trim );

sub handler
{
    my( $req ) = @_;

    # Authorization
    if( $Para::Frame::U->chat_level < 4 )
    {
 	throw('denied', "Endast för ops");
    }

    my $q = $req->q;

    my $pattern = $q->param('pattern');
    my $reason  = $q->param('reason');
    my $expire  = $q->param('expire');

    if( $q->param('remove') )
    {
	my $sth = $Para::dbh->prepare_cached("delete from ipfilter where ipfilter_pattern=?");
	$sth->execute( $pattern );
	return "Filter removed\n";
    }


    if( length $expire )
    {
	$expire = date( $expire );
	$expire or throw('validate', 'Inget bra datumformat');
	$expire = $Para::dbix->format_datetime( $expire );
    }
    else
    {
	$expire = undef;
    }

    my $m = $Para::Frame::U;
    my $updated   = now();
    my $updated_out = $Para::dbix->format_datetime( $updated );
    trim( \$reason );

    unless( $reason )
    {
	throw('validate', "Ge en anledning");
    }


    # Store payment record
    #
    my $sth = $Para::dbh->prepare_cached("update ipfilter set ipfilter_reason=?, ipfilter_expire=?, ipfilter_changedby=?, ipfilter_updated=? where ipfilter_pattern=?");

    $sth->execute( $reason, $expire, $m->id, $updated_out, $pattern );

    return "Filter updated\n";
};

1;
