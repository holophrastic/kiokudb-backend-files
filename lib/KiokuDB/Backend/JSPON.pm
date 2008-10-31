#!/usr/bin/perl

package KiokuDB::Backend::JSPON;
use Moose;

use Carp qw(croak);

use File::NFSLock;
use IO::AtomicFile;
use JSON;

use Data::Stream::Bulk::Path::Class;

use MooseX::Types::Path::Class qw(Dir File);

use namespace::clean -except => 'meta';

our $VERSION = "0.02";

with qw(
    KiokuDB::Backend
    KiokuDB::Backend::Serialize::JSPON
    KiokuDB::Backend::UnicodeSafe
    KiokuDB::Backend::Clear
    KiokuDB::Backend::Scan
    KiokuDB::Backend::Query::Simple::Linear
);

sub BUILD {
    my $self = shift;
    $self->create_dirs;
}

has dir => (
    isa => Dir,
    is  => "ro",
    required => 1,
    coerce   => 1,
);

has object_dir => (
    isa => Dir,
    is  => "ro",
    lazy_build => 1,
);

# TODO implement trie fanning on disk
has trie => (
    isa => "Bool",
    is  => "ro",
    default => 0,
);

# how many hex nybbles per trie level
has trie_nybbles => (
    isa => "Int",
    is  => "rw",
    default => 3, # default 4096 entries per level
);

# /dec/afb/decafbad
has trie_levels => (
    isa => "Int",
    is  => "rw",
    default => 2,
);

sub _build_object_dir {
    my $self = shift;
    $self->dir->subdir("all");
}

has root_set_dir => (
    isa => Dir,
    is  => "ro",
    lazy_build => 1,
);

sub _build_root_set_dir {
    my $self = shift;
    $self->dir->subdir("root");
}

has lock => (
    isa => "Bool",
    is  => "rw",
    default => 1,
);

has lock_file => (
    isa => File,
    is  => "ro",
    lazy_build => 1,
);

sub _build_lock_file {
    my $self = shift;
    $self->dir->file("lock");
}

has pretty => (
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has json => (
    isa => "Object",
    is  => "rw",
    lazy_build => 1,
    handles => [qw(encode decode)],
);

sub _build_json {
    my $self = shift;
    my $json = JSON->new->canonical;
    $json->pretty if $self->pretty;
    return $json;
}

sub write_lock {
    my $self = shift;

    return 1 unless $self->lock;

    File::NFSLock->new({ file => $self->lock_file->stringify, lock_type => "EXCLUSIVE" });
}

sub get {
    my ( $self, @uids ) = @_;

    if ( @uids == 1 ) {
        return $self->get_entry($uids[0]);
    } else {
        return map { $self->get_entry($_) } @uids;
    }
}

sub insert {
    my ( $self, @entries ) = @_;

    foreach my $entry ( @entries ) {
        $self->insert_entry($entry);
    }
}

sub delete {
    my ( $self, @ids_or_entries ) = @_;

    my @uids = map { ref($_) ? $_->id : $_ } @ids_or_entries;

    foreach my $uid ( @uids ) {
        foreach my $file ( $self->object_file($uid), $self->root_set_file($uid) ) {
            $file->remove;
        }
    }
}

sub exists {
    my ( $self, @uids ) = @_;

    map { -e $self->object_file($_) } @uids;
}

sub get_entry {
    my ( $self, $uid ) = @_;

    my ( $json, @attrs ) = $self->read_entry($uid);

    my $data = $self->decode($json);

    my $entry = $self->expand_jspon($data, @attrs);

    return $entry;
}

sub insert_entry {
    my ( $self, $entry ) = @_;

    my $data = $self->collapse_jspon($entry);

    $self->write_entry( $entry => $self->encode($data) );
}

sub read_entry {
    my ( $self, $id ) = @_;

    $self->slurp_file($self->object_file($id));
}

sub slurp_file {
    my ( $self, $file ) = @_;

    my $fh = $file->openr || croak("slurp_file($file): $!");

    $fh->binmode(":utf8");

    my $data = do { local $/; <$fh> };

    return $data;
}

sub write_entry {
    my ( $self, $entry, $json ) = @_;

    my $id = $entry->id;

    my $file = $self->object_file($id);

    my $fh = IO::AtomicFile->open( $file, "w" );

    $fh->binmode(":utf8");

    $fh->print( $json );

    {
        my $lock = $self->write_lock;

        $fh->close || croak "Couldn't store: $!";

        my $root_file = $self->root_set_file($id);
        $root_file->remove;
        link( $file, $root_file ) if $entry->root;
    }
}

sub object_file {
    my ( $self, $uid ) = @_;
    $self->object_dir->file($uid);
}

sub root_set_file {
    my ( $self, $uid ) = @_;
    $self->root_set_dir->file($uid);
}

sub create_dirs {
    my $self = shift;

    $self->object_dir->mkpath;
    $self->root_set_dir->mkpath;
}

sub clear {
    my $self = shift;

    $_->rmtree({ keep_root => 1 }) for $self->root_set_dir, $self->object_dir;
}

sub all_entries {
    my $self = shift;

    my $root_set_dir = $self->root_set_dir;

    Data::Stream::Bulk::Path::Class->new( dir => $self->object_dir, only_files => 1 )->filter(sub { [ map {
        my $json = $self->slurp_file($_);
        my $root = -e $root_set_dir->file($_->basename);
        my $data = $self->decode($json);

        $self->expand_jspon( $data, ( $root ? ( root => 1 ) : () ) );
    } @$_ ]});
}

sub root_entries {
    my $self = shift;

    Data::Stream::Bulk::Path::Class->new( dir => $self->root_set_dir, only_files => 1 )->filter(sub { [ map {
        my $json = $self->slurp_file($_);
        my $data = $self->decode($json);
        $self->expand_jspon( $data, root => 1 );
    } @$_ ]});
}

__PACKAGE__->meta->make_immutable;

__PACKAGE__

__END__

=pod

=head1 NAME

KiokuDB::Backend::JSPON - JSON file backend with JSPON
reference semantics

=head1 DESCRIPTION

L<http://www.jspon.org/|JSPON> is a standard for encoding object graphs in
JSON.

The representation is based on explicit ID based references, and so is simple
enough to be stored in JSON.

=head1 TODO

=over 4

=item *

Refactor into FS role and general JSPON role, and implement a REST based
backend too

=back

=cut
