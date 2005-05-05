#  $Id$  -*-perl-*-
package Para::Utils;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Utils class
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

=head1 NAME

Para::Utils - Utility functions for paranormal.se

=cut


BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use base qw( Exporter );
BEGIN
{
    our @EXPORT_OK = qw( cache_update );

}

sub cache_update
{
    ### TODO: Fix real caching
    $Psi::Cache::Changed = time;
}

1;
