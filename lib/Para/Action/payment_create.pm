#  $Id$  -*-perl-*-
package Para::Action::payment_create;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw trim );
use Para::Frame::Time qw( date );

use Para::Constants qw( MONTH_LENGTH T_PRENUMERATION T_PARANORMAL_SWEDEN );
use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->id != 1 )
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
    my $receiver   = Para::Topic->get_by_id( T_PARANORMAL_SWEDEN );
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
    my $sth = $Para::dbh->prepare_cached("insert into payment
      ( payment_id, payment_member, payment_company, payment_date, payment_order_date, payment_invoice_date, payment_product, payment_price, payment_vat, payment_quantity, payment_method, payment_receiver, payment_receiver_vernr, payment_message, payment_comment )
      values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");

    my $product_id  = $product->id;
    my $method_id   = $method->id;
    my $receiver_id = $receiver->id;

    my $company_id = $company ? Para::Topic->find_one( $company )->id : undef;
    my $mid = $m->id;

    my $payment_date_cdate = $payment_date ? $payment_date->cdate : undef;
    my $order_date_cdate   = $order_date   ? $order_date->cdate   : undef;
    my $invoice_date_cdate = $invoice_date ? $invoice_date->cdate : undef;
    my $log_date_cdate     = $log_date     ? $log_date->cdate     : undef;

    $sth->execute( $order_id, $mid, $company_id,
		   $payment_date_cdate, $order_date_cdate,
		   $invoice_date_cdate, $product_id, $price, $vat,
		   $quantity, $method_id, $receiver_id, $vernr,
		   $message, $comment );

    my $payment = Para::Payment->new( $order_id );
    $payment->set_completed( $reference );

    return "Payment record recorded\n";
}

1;