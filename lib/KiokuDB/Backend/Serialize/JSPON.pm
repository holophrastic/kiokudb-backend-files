#!/usr/bin/perl

package KiokuDB::Backend::Serialize::JSPON;
use Moose::Role;

use KiokuDB::Backend::Serialize::JSPON::Expander;
use KiokuDB::Backend::Serialize::JSPON::Collapser;

use namespace::clean -except => 'meta';

has expander => (
    isa => "KiokuDB::Backend::Serialize::JSPON::Expander",
    is  => "rw",
    lazy_build => 1,
    handles => [qw(expand_jspon)],
);

sub _build_expander {
    my $self = shift;
    KiokuDB::Backend::Serialize::JSPON::Expander->new();
}

has collapser => (
    isa => "KiokuDB::Backend::Serialize::JSPON::Collapser",
    is  => "rw",
    lazy_build => 1,
    handles => [qw(collapse_jspon)],
);

sub _build_collapser {
    my $self = shift;
    KiokuDB::Backend::Serialize::JSPON::Collapser->new();
}

__PACKAGE__

__END__

=pod

=head1 NAME

KiokuDB::Backend::Serialize::JSPON -

=head1 SYNOPSIS

	with qw(KiokuDB::Backend::Serialize::JSPON);

=head1 DESCRIPTION

=cut


