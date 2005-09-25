#  $Id$  -*-perl-*-
package Para::Payment;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Member Payment class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Data::Dumper;
use Carp;
use MIME::Lite;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Time qw( duration );
use Para::Frame::Utils qw( debug );

use Para::Topic;
use Para::Member;
use Para::Constants qw( MONTH_LENGTH T_PRENUMERATION T_PARANORMAL_SWEDEN );

sub new
{
    my( $this, $rec ) = @_;
    my $class = ref($this) || $this;

    if( ref $rec eq 'HASH' )
    {
	# Assume it's the payment record
    }
    elsif( $rec =~ /^\d+$/ )
    {
	$rec = $Para::dbix->select_possible_record("from payment where payment_id=?", $rec);
	return undef unless $rec;
    }
    else
    {
	die "Bad id '$rec'";
    }

    return bless( $rec, $class );
}

sub id        { $_[0]->{'payment_id'} }
sub member    { Para::Member->get( $_[0]->{'payment_member'} ) }
sub company
{
    return  $_[0]->{'payment_company'} ? Para::Topic->get_by_id( $_[0]->{'payment_company'} ) : undef;
}

sub date
{
    return $_[0]->payment_date;
}

sub payment_date
{
    unless( ref $_[0]->{'payment_date'} )
    {
	return $_[0]->{'payment_date'} =
	    Para::Frame::Time->get($_[0]->{'payment_date'} );
    }
    return $_[0]->{'payment_date'};
}


sub order_date
{
    unless( ref $_[0]->{'payment_order_date'} )
    {
	return $_[0]->{'payment_order_date'} =
	    Para::Frame::Time->get($_[0]->{'payment_order_date'} );
    }
    return $_[0]->{'payment_order_date'};
}

sub invoice_date
{
    unless( ref $_[0]->{'payment_invoice_date'} )
    {
	return $_[0]->{'payment_invoice_date'} =
	    Para::Frame::Time->get($_[0]->{'payment_invoice_date'} );
    }
    return $_[0]->{'payment_invoice_date'};
}

sub log_date
{
    unless( ref $_[0]->{'payment_log_date'} )
    {
	return $_[0]->{'payment_log_date'} =
	    Para::Frame::Time->get($_[0]->{'payment_log_date'} );
    }
    return $_[0]->{'payment_log_date'};
}


sub product   { Para::Topic->get_by_id($_[0]->{'payment_product'} ) }
sub price     { $_[0]->{'payment_price'} }
sub vat       { $_[0]->{'payment_vat'} }
sub quantity  { $_[0]->{'payment_quantity'} }
sub method    { Para::Topic->get_by_id($_[0]->{'payment_method'} ) }
sub receiver  { Para::Topic->get_by_id($_[0]->{'payment_receiver'} ) }
sub vernr     { $_[0]->{'payment_receiver_vernr'} }
sub reference { $_[0]->{'payment_reference'} }
sub comment   { $_[0]->{'payment_comment'} }
sub message   { $_[0]->{'payment_message'} }
sub completed { $_[0]->{'payment_completed'} }

sub set_completed
{
    my( $p, $reference ) = @_;

    my $sth = $Para::dbh->prepare("update payment set payment_completed=true, payment_reference=?, payment_date=?, payment_log_date=now() where payment_id=?");

    my $payment_date = $p->payment_date ? $p->payment_date->cdate : Para::Frame::Time->now()->cdate;
    $sth->execute( $reference, $payment_date, $p->id );

    my $body = "Betalning från ".$p->member->name."\n";
    $body .= "http://paranormal.se/member/db/person/order/details?pid=".$p->id."\n\n";
    if( $p->message )
    {
	$body .= "\nMeddelande:\n";
	$body .= $p->message;
    }
    if( $p->comment )
    {
	$body .= "\n\nKommentar:\n";
	$body .= $p->comment;
    }

    my $subject = "Betalning via webben: ".$p->price." kr";

    my $msg = MIME::Lite->new(
			      From     => $p->member->sys_email,
			      To       => 'money@paranormal.se',
			      Subject  => $subject,
			      Type     => 'TEXT',
			      Data     => $body,
			      Encoding => 'quoted-printable',
			     );
    $msg->send;

    $p->add_to_member_stats;
    $p->member->publish;
}

sub add_to_member_stats
{
    my( $p ) = @_;

    if( $p->product->id == T_PRENUMERATION and $p->receiver->id == T_PARANORMAL_SWEDEN )
    {
	my $m = $p->member;

	debug sprintf "Add stats for payment %d to %s", $p->id, $m->name;

	my $length     = $p->quantity;
	my $member     = $p->member;
	my $old_expire = $m->payment_expire;
	my $date       = Para::Frame::Time->get(time);
#	warn "$$:     date is $date\n";
#	warn "$$:     old_expire is $old_expire\n";
	$old_expire    = $date if $date > $old_expire;
	my $new_expire = Para::Frame::Time->get( $old_expire + duration( days => $length ) );
	my $cost       = $p->price;
	my $total      = $m->payment_total + $cost;

	$m->{'member_payment_period_length'} = $length;
	$m->{'member_payment_period_expire'} = $new_expire->cdate;
	$m->{'member_payment_period_cost'}   = $cost;
	$m->{'member_payment_total'}         = $total;

	$m->mark_unsaved;

	debug "Total is now $total";
    }
}

1;
