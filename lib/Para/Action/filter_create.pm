package Para::Action::filter_create;

use strict;

use Para::Frame::Time qw( date now );
use Para::Frame::Utils qw( throw trim );
use Para::Constants qw( MONTH_LENGTH T_PRENUMERATION T_PARANORMAL_SWEDEN );

sub handler
{
    my( $req ) = @_;

    # Authorization
    if( $Para::Frame::U->chat_level < 4 )
    {
 	throw('denied', "Endast för Ops");
    }

    my $q = $req->q;


    my $pattern = $q->param('pattern');
    my $reason  = $q->param('reason');
    my $expire  = $q->param('expire');

    if( length $expire )
    {
	$expire = date( $expire );
	$expire or throw('validate', 'Inget bra datumformat');
	$expire = $expire->ymd;
    }
    else
    {
	$expire = undef;
    }

    my $m = $Para::Frame::U;
    my $created   = now();
    trim( \$reason );

    unless( $reason )
    {
	throw('validate', "Ge en anledning");
    }


    # Store payment record
    #
    my $sth = $Para::dbh->prepare_cached("insert into ipfilter
      ( ipfilter_pattern, ipfilter_createdby, ipfilter_created, ipfilter_changedby, ipfilter_updated, ipfilter_expire, ipfilter_reason )
      values ( ?, ?, ?, ?, ?, ?, ?)");

    $sth->execute( $pattern, $m->id, $created->cdate, $m->id, $created->cdate, $expire, $reason );

    return "Filter created\n";
};

1;
