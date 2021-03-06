# -*-cperl-*-
package Para::Action::payment_create;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw trim );
use Para::Frame::Time qw( date );

use Para::Topic;
use Para::Constants qw( $C_T_PARANORMAL_SWEDEN );

sub handler
{
	my( $req ) = @_;

	my $q = $req->q;
	my $u = $req->s->u;

	if ( $u->id != 1 )
	{
		throw('denied', "Endast f�r No1");
	}



	my $order_date       =  $q->param('order_date') ?
		date( $q->param('order_date') ) : undef;
	my $invoice_date     = $q->param('invoice_date') ?
		date( $q->param('invoice_date') ) : undef;
	my $payment_date     = $q->param('payment_date') ?
		date( $q->param('payment_date') ) : undef;
	my $log_date         = $q->param('log_date') ?
		date( $q->param('log_date') ) : undef;


	my $m          = Para::Member->get_by_nickname( $q->param('nickname') );
	my $company    = $q->param('company') || undef;
	my $product    = Para::Topic->get_by_id( $q->param('product') );
	my $price      = $q->param('price');
	my $vat        = $q->param('vat');
	my $quantity   = $q->param('quantity');
	my $method     = Para::Topic->get_by_id( $q->param('method') );
	my $receiver   = Para::Topic->get_by_id( $C_T_PARANORMAL_SWEDEN );
	my $vernr      = $q->param('vernr');
	my $reference  = $q->param('reference');
	my $comment    = $q->param('comment');
	my $message    = $q->param('message');

	$vat        ||= $price * .20;

	trim( \$comment );
	trim( \$message );

	unless( $price )
	{
		throw('validate', "price to low");
	}

	my $order_id = $Para::dbix->get_nextval( "t_seq" );


	# Store payment record
	#
	my $sth = $Para::dbh->prepare("insert into payment
      ( payment_id, payment_member, payment_company, payment_date, payment_order_date, payment_invoice_date, payment_product, payment_price, payment_vat, payment_quantity, payment_method, payment_receiver, payment_receiver_vernr, payment_message, payment_comment )
      values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");

	my $product_id  = $product->id;
	my $method_id   = $method->id;
	my $receiver_id = $receiver->id;

	my $company_id = $company ? Para::Topic->find_one( $company )->id : undef;
	my $mid = $m->id;

	my $payment_date_out = $payment_date ?
		$Para::dbix->format_datetime($payment_date) : undef;
	my $order_date_out   = $order_date   ?
		$Para::dbix->format_datetime($order_date)   : undef;
	my $invoice_date_out = $invoice_date ?
		$Para::dbix->format_datetime($invoice_date) : undef;
	my $log_date_out     = $log_date     ?
		$Para::dbix->format_datetime($log_date)     : undef;

	$sth->execute( $order_id, $mid, $company_id,
								 $payment_date_out, $order_date_out,
								 $invoice_date_out, $product_id, $price, $vat,
								 $quantity, $method_id, $receiver_id, $vernr,
								 $message, $comment );

	my $payment = Para::Payment->new( $order_id );
	$payment->set_completed( $reference );

	return "Payment record recorded\n";
}

1;
