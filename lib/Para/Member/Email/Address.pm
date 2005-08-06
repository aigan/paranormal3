#  $Id$  -*-perl-*-
package Para::Member::Email;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Member Email class
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

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Time;

use Para::Member;

use base 'Para::Email::Address';

sub new
{
    my( $this, $m, $email_str, $rec ) = @_;
    my $class = ref($this) || $this;

    $m ||= $Para::Frame::U;

    my $ea = $class->parse( $email_str );

    if( $rec )
    {
	$ea->equals( $rec->{mailalias} ) or die "record mismatch";
	$rec->{mailalias_member} == $m->id or die "record mismatch";
    }
    else
    {
	$rec = $Para::dbix->select_record('from mailalias where mailalias_member=? and mailalias=?', $m->id, $ea->as_string );

	$rec or die "Email $email_str is not coupled to member ".$m->id."\n";
    }

    # Copy to Para::Email::Address object
    foreach my $key ( keys %$rec )
    {
	$ea->{$key} = $rec->{$key};
    }

    return bless( $ea, $class );
}

sub add
{
    my( $this, $m, $email_address_in ) = @_;
    my $class = ref($this) || $this;

    my $ea = $class->parse( $email_address_in );

    my $st = "insert into mailalias
              ( mailalias_member, mailalias, mailalias_created )
              values ( ?, ?, now() )";
    my $sth = $Para::dbh->prepare_cached( $st );
    eval
    {
	$sth->execute($m->id, $ea->address);
    };
    if( $@ )
    {
	warn "Error: $@";
	if( $Para::dbh->errstr and $Para::dbh->errstr =~ /duplicate key/ )
	{
	    if( $Para::dbh->errstr =~ /mailalias_pkey/ )
	    {
		# Must throw an error
		throw('validation', "E-postadressen '$email_address_in' är knuten till en annan medlems alternativa e-postadresser\nÄr det din adress kan du få lösenordet postat till dig för det existerande medlemskapet");
	    }
	}
	die $@;
    }
    $sth->rows and return 1;
    return 0;
}

sub delete
{
    my( $e ) = @_;

    my $m = $e->member;

    # Do not allow to remove an alias if its the sys_email
    if( $m->sys_email->equals($e) )
    {
	throw('email', "Du kan inte ta bort din primära e-postadress");
    }

    my $st = "delete from mailalias where
              mailalias_member=? and mailalias=?";
    my $sth = $Para::dbh->prepare_cached( $st );
    $sth->execute($m->id, $e->as_string);
    $sth->rows and return 1;
    return 0;
}

# sub as_string
# {
#     return $_[0]->{mailalias};
# }

# sub equals
# {
#     my( $e, $e2_in) = @_;
# 
#     my $e2_as_string;
#     if( ref $e2_in )
#     {
# 	if( $e2_in->isa('Para::Frame::Email::Address') )
# 	{
# 	    $e2_as_string = $e2_in->as_string;
# 	}
# 	else
# 	{
# 	    die;
# 	}
#     }
#     else
#     {
# 	$e2_as_string = $e2_in;
#     }
# 
#     return $e2_as_string eq $e->as_string;
# }

sub member
{
    my( $e ) = @_;
    return Para::Member->get( $e->{'mailalias_member'} )
}

sub created
{
    my( $e ) = @_;
    return Para::Frame::Time->get( $e->{'mailalias_created'} )
}

sub working
{
    my( $e ) = @_;
    return Para::Frame::Time->get( $e->{'mailalias_working'} )
}

sub failed
{
    my( $e ) = @_;
    return $e->{'mailalias_failed'};
}


1;
