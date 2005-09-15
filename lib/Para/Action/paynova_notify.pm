#  $Id$  -*-perl-*-
package Para::Action::paynova_notify;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Paynova notify action
#   This is a Apache Handler module, separate from Paraframe
#
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Digest::MD5  qw(md5_hex);
use CGI;
use MIME::Lite;
use Data::Dumper;
use Unicode::MapUTF8 qw( to_utf8 );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( debug );
use Para::Frame::Time;

use Para::Payment;

sub handler
{
    my( $req ) = shift;

    # This handler recieves payment confirmation (PaymentPOST) from Paynova.

    debug "Paynova_notify from $ENV{REMOTE_ADDR}";

    my $q = $req->q;
    my $u = $req->s->u;

    my $secret_key = $Para::SITE_CFG->{'paynova'}{'secret_key'};


    my $trans_id = $q->param("trans_id");
    # The Paynova transaction ID. Length 18 characters.

    my $status = $q->param("paymentstatus") || -1;
    # 1 = OK , -1 = Failed

    my $order_id = $q->param("order_id") || '';

    my $checksum_recieved = $q->param("checksum") || '';
    # Recieved checksum.

    my $checksum = md5_hex( $status, $order_id, $trans_id, $secret_key );

    if( debug )
    {
#	debug "checksum_calculated: $checksum\n";
#	debug "checksum_recieved  : $checksum_recieved\n";
#	debug "$trans_id|$status|$order_id\n";

	foreach my $key ( $q->param() )
	{
	    debug " Key $key: ".$q->param($key)."\n";
	}
    }


    my $out = "";
    if( $checksum eq $checksum_recieved )
    {
	if( $status eq "1" )
	{
	    if( not confirm_payment($order_id, $trans_id) )
	    {
		$out .= "CANCEL|Uppgifterna har försvunnit. Ni måste börja om!";
	    }
	    else
	    {
		# To be able to confirm the POST, Paynova requires the
		# first two characters in the response to be "OK".
		#
		$out .= "OK|OK";
	    }
	}
	else
	{
	    cancel_payment($order_id);
	    $out .= "OK|Cancelled";
	}
    }
    else
    {
	# Do not cancel the payment, since we can't trust the order_id

	$out .= "Error|Checksum mismatch!";

	if( debug )
	{
#	    debug "-----\n";
	    debug "checksum_calculated: $checksum\n";
	    debug "checksum_recieved  : $checksum_recieved\n";
	    debug "$trans_id|$status|$order_id\n";
	}

    }

    $req->{'renderer'} = sub
    {
	$req->{'page'} = \$out;
	$req->{'page_sender'} = 'bytes';
    };

#    $r->status(200);
#    $r->header_out( 'Connection', 'close' );
#    $r->header_out( 'Content-Length', length($out) );
#    $r->send_http_header('text/html');
#    $r->print( to_utf8({ -string => $out, -charset => 'ISO-8859-1'}) );
    debug "$out\n";

    return "";
}

sub cancel_payment
{
    my( $order_id ) = @_;

    my $sth = $Para::dbh->prepare_cached("delete from payment where payment_id=?");
    $sth->execute( $order_id );

}

sub confirm_payment
{
    my( $order_id, $trans_id ) = @_;

    my $payment = Para::Payment->new( $order_id ) or return 0;
    $payment->set_completed( $trans_id ); # TODO: Tiny race condition here
    return 1;
}

1;
