# -*-cperl-*-
package Para::Action::paynova_begin;

use strict;
use Data::Dumper;
use Digest::MD5  qw(md5_hex);
use LWP::Simple;

use Para::Frame::Utils qw( throw trim );
use Para::Frame::Time qw( now duration );

use Para::Topic;
use Para::Constants qw( $C_T_PRENUMERATION $C_T_PARANORMAL_SWEDEN $C_T_PAYNOVA $C_MONTH_LENGTH );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 1 )
    {
	throw('denied', "Logga in först");
    }

    my $m         = $u;
    my $mid       = $m->id;
    my $length    = 0 + $q->param('length');
    my $worth     = 0 + $q->param('worth');
    my $message   = $q->param('message');
    trim( \$message );

    warn "Starting paynova session for $mid for $length days at the $worth rate\n";

    my $host = $req->host;
    my $server_url         = "http://$host/member/payment/";
#    my $server_url_secure  = "https://paranormal.se/member/payment/";
    my $server_url_secure  = $server_url;
    my $paynova_server_url = "https://www.paynova.com/";

    my $icp_account_id = $Para::SITE_CFG->{'paynova'}{'icp_account_id'};
    my $secret_key     = $Para::SITE_CFG->{'paynova'}{'secret_key'};



    my $month_length = $C_MONTH_LENGTH;
    my $amount_kr = int($worth * $length / $month_length );
    $amount_kr = 1 if $amount_kr < 1;

    my $vat = $amount_kr * .20; # Moms with 25% on top of the price

    my $amount = $amount_kr * 100; # Don't use decimals.
    my $currency = "SEK";

    my $order_id = $Para::dbix->get_nextval( "t_seq" );

    # The web page that will recieve the payment confirmation
    # post. Enter a complete URL with https://.
    #
    my $notifypage = $server_url_secure . "notify.cgi";

    # The web page that the customer will be redirected to if the
    # payment has been successful. Enter a complete URL with http://
    # or https://.
    #
    my $redirect_url_ok = $server_url . "thanks.tt?oid=$order_id";

    # The web page that the customer will be redirected to if the
    # payment has not been successful. Enter a complete URL with
    # http:// or https://.
    #
    my $redirect_url_cancel = $server_url . "cancelled.tt?oid=$order_id";


    # Store preliminary payment record (without price)
    #
    my $sth = $Para::dbh->prepare("insert into payment
      ( payment_id, payment_member, payment_company, payment_date, payment_order_date, payment_invoice_date, payment_log_date, payment_product, payment_price, payment_vat, payment_quantity, payment_method, payment_receiver, payment_message )
      values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");

    my $product_id  = $C_T_PRENUMERATION;
    my $method_id   = $C_T_PAYNOVA;
    my $receiver_id = $C_T_PARANORMAL_SWEDEN;
    my $today = now();
    my $today_out = $Para::dbix->format_datetime( $today );

    my $vat_db = $vat;
    $vat_db =~ s/,/./;

    $sth->execute( $order_id, $mid, undef, undef, $today_out,
		   $today_out, undef, $product_id, $amount_kr,
		   $vat_db, $length, $method_id, $receiver_id, $message
		   );

    # Get the current payment_period_expire date
    #
    my $old_expire = $m->payment_expire;
    if( $today > $old_expire )
    {
	$old_expire = $today;
    }

    my $new_expire = $old_expire + duration(days => $length );


    # Contract text. This text is displayed in the wallet and should
    # describe what the customer is paying for.
    #
    my $contract_text = ( "Gåva till Paranormal Sweden motsvarande\r\n"
			  ."$worth kr/månad under $length dagar.\r\n"
			);

    $contract_text .= ( sprintf "Moms (25%%) ingår med %.2f kr.\r\n", $vat );

    if( $today < $old_expire )
    {
	if( $m->payment_total == 0 )
	{
	    $contract_text .= ( "Tillsammans med din 'gratisperiod' sträcker\r\n"
				."sig din prenumeration till " );
	}
	else
	{
	    $contract_text .= ( "Tillsammans med dina tidigare gåvor\r\n"
				."sträcker sig nu din prenumeration till\t\n" );
	}
    }
    else
    {
	$contract_text .= ( "Din prenumeration sträcker sig till\r\n" );
    }

    $contract_text .= $new_expire->ymd . ".\r\n";

    my $checksum = md5_hex( $icp_account_id, $amount, $currency,
			    $notifypage, $redirect_url_ok,
			    $redirect_url_cancel, $order_id,
			    $contract_text, $secret_key
			  );

    my %data =
    (
     icpaccountid      => $icp_account_id,
     amount            => $amount,
     currency          => $currency,
     orderid           => $order_id,
     notifypage        => $notifypage,
     redirecturlok     => $redirect_url_ok,
     redirecturlcancel => $redirect_url_cancel,
     contracttext      => $contract_text,
     checksum          => $checksum,
    );

#    warn Dumper \%data;

    my $post_data = join '&', map {$_."=".$q->escape($data{$_})} keys %data;

    # Make the payment request (IcpPOST) and read the sessionkey
    # returned. You can use either POST or GET.
    #
    my $complete_url = $paynova_server_url . "payment/startpayment.asp?" . $post_data;
    my $session_key = get($complete_url);


    # Check that the sessionkey is correct. Always 37 characters.
    # If the sessionkey != 37 characters, it may contain an error message.

    if( length($session_key) == 37 )
    {
	$req->response->redirect($paynova_server_url
			     . "/wallet/default.asp?sessionKey="
			     . $session_key);
    }
    else
    {
	# Illegal sessionkey
	$q->param('debug_info', $session_key );
	warn "complete_url: $complete_url\n";

	throw('action', "Ett fel uppstod. Kontakta info\@paranormal.se");
    }

    return "";

}

1;
