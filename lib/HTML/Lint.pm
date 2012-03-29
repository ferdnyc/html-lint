package HTML::Lint;

use warnings;
use strict;

use HTML::Lint::Error;
use HTML::Entities ();

=head1 NAME

HTML::Lint - check for HTML errors in a string or file

=head1 VERSION

Version 2.11_01

=cut

our $VERSION = '2.11_01';

=head1 SYNOPSIS

    my $lint = HTML::Lint->new;
    $lint->only_types( HTML::Lint::Error::STRUCTURE );

    $lint->parse( $data );
    $lint->parse_file( $filename );

    my $error_count = $lint->errors;

    foreach my $error ( $lint->errors ) {
        print $error->as_string, "\n";
    }

HTML::Lint also comes with a wrapper program called F<weblint> that handles
linting from the command line:

    $ weblint http://www.cnn.com/
    http://www.cnn.com/ (395:83) <IMG SRC="spacer.gif"> tag has no HEIGHT and WIDTH attributes.
    http://www.cnn.com/ (395:83) <IMG SRC="goofus.gif"> does not have ALT text defined
    http://www.cnn.com/ (396:217) Unknown element <nobr>
    http://www.cnn.com/ (396:241) </nobr> with no opening <nobr>
    http://www.cnn.com/ (842:7) target attribute in <a> is repeated

And finally, you can also get L<Apache::HTML::Lint> that passes any
mod_perl-generated code through HTML::Lint and get it dumped into your
Apache F<error_log>.

    [Mon Jun  3 14:03:31 2002] [warn] /foo.pl (1:45) </p> with no opening <p>
    [Mon Jun  3 14:03:31 2002] [warn] /foo.pl (1:49) Unknown element <gronk>
    [Mon Jun  3 14:03:31 2002] [warn] /foo.pl (1:56) Unknown attribute "x" for tag <table>

=cut

=head1 METHODS

NOTE: Some of these methods mirror L<HTML::Parser>'s methods, but HTML::Lint
is not a subclass of HTML::Parser.

=head2 new()

Create an HTML::Lint object, which inherits from HTML::Parser.
You may pass the types of errors you want to check for in the
C<only_types> parm.

    my $lint = HTML::Lint->new( only_types => HTML::Lint::Error::STRUCTURE );

If you want more than one, you must pass an arrayref:

    my $lint = HTML::Lint->new(
        only_types => [HTML::Lint::Error::STRUCTURE, HTML::Lint::Error::FLUFF] );

=cut

sub new {
    my $class = shift;
    my %args = @_;

    my $self = {
        _errors => [],
        _types  => [],
    };
    bless $self, $class;

    if ( my $only = $args{only_types} ) {
        $self->only_types( ref $only eq 'ARRAY' ? @{$only} : $only );
        delete $args{only_types};
    }

    warn "Unknown argument $_\n" for keys %args;

    return $self;
}

=head2 $lint->parser()

Returns the parser object for this object, creating one if necessary.

=cut

sub parser {
    my $self = shift;

    if ( not $self->{_parser} ) {
        $self->{_parser} = HTML::Lint::Parser->new( sub { $self->gripe( @_ ) } );
        $self->{_parser}->ignore_elements( qw(script style) );
    }

    return $self->{_parser};
}

=head2 $lint->parse( $text )

=head2 $lint->parse( $code_ref )

Passes in a chunk of HTML to be linted, either as a piece of text,
or a code reference.
See L<HTML::Parser>'s C<parse_file> method for details.

=cut

sub parse {
    my $self = shift;

    return $self->parser->parse( @_ );
}

=head2 $lint->parse_file( $file )

Analyzes HTML directly from a file. The C<$file> argument can be a filename,
an open file handle, or a reference to an open file handle.
See L<HTML::Parser>'s C<parse_file> method for details.

=cut

sub parse_file {
    my $self = shift;
    return $self->parser->parse_file( @_ );
}

=head2 $lint->eof

Signals the end of a block of text getting passed in.  This must be
called to make sure that all parsing is complete before looking at errors.

Any parameters (and there shouldn't be any) are passed through to
HTML::Parser's eof() method.

=cut

sub eof {
    my $self = shift;

    my $rc;
    my $parser = $self->parser;
    if ( $parser ) {
        $rc = $self->parser->eof(@_);
        delete $self->{_parser};
    }

    return $rc;
}

=head2 $lint->errors()

In list context, C<errors> returns all of the errors found in the
parsed text.  Each error is an object of the type L<HTML::Lint::Error>.

In scalar context, it returns the number of errors found.

=cut

sub errors {
    my $self = shift;

    if ( wantarray ) {
        return @{$self->{_errors}};
    }
    else {
        return scalar @{$self->{_errors}};
    }
}

=head2 $lint->clear_errors()

Clears the list of errors, in case you want to print and clear, print and clear.

=cut

sub clear_errors {
    my $self = shift;

    $self->{_errors} = [];

    return;
}

=head2 $lint->only_types( $type1[, $type2...] )

Specifies to only want errors of a certain type.

    $lint->only_types( HTML::Lint::Error::STRUCTURE );

Calling this without parameters makes the object return all possible
errors.

The error types are C<STRUCTURE>, C<HELPER> and C<FLUFF>.
See L<HTML::Lint::Error> for details on these types.

=cut

sub only_types {
    my $self = shift;

    $self->{_types} = [@_];

    return;
}

=head2 $lint->gripe( $errcode, [$key1=>$val1, ...] )

Adds an error message, in the form of an L<HTML::Lint::Error> object,
to the list of error messages for the current object.  The file,
line and column are automatically passed to the L<HTML::Lint::Error>
constructor, as well as whatever other key value pairs are passed.

For example:

    $lint->gripe( 'attr-repeated', tag => $tag, attr => $attr );

Usually, the user of the object won't call this directly, but just
in case, here you go.

=cut

sub gripe {
    my $self = shift;

    my $error = HTML::Lint::Error->new(
        $self->{_file}, $self->parser->{_line}, $self->parser->{_column}, @_ );

    my @keeps = @{$self->{_types}};
    if ( !@keeps || $error->is_type(@keeps) ) {
        push( @{$self->{_errors}}, $error );
    }

    return;
}

=head2 $lint->newfile( $filename )

Call C<newfile()> whenever you switch to another file in a batch
of linting.  Otherwise, the object thinks everything is from the
same file.  Note that the list of errors is NOT cleared.

Note that I<$filename> does NOT need to match what's put into parse()
or parse_file().  It can be a description, a URL, or whatever.

=cut

sub newfile {
    my $self = shift;
    my $file = shift;

    delete $self->{_parser};
    $self->{_file} = $file;
    $self->{_line} = 0;
    $self->{_column} = 0;
    $self->{_first_seen} = {};

    return $self->{_file};
} # newfile

=pod

HTML::Lint::Parser is a class only for this module.

=cut

package HTML::Lint::Parser;

use HTML::Parser 3.20;
use HTML::Tagset 3.03;

use HTML::Lint::HTML4 qw( %isKnownAttribute %isRequired %isNonrepeatable %isObsolete );
use HTML::Entities qw( %char2entity );

use base 'HTML::Parser';

sub new {
    my $class = shift;
    my $gripe = shift;

    my $self =
        HTML::Parser->new(
            api_version => 3,
            start_document_h   => [ \&_start_document, 'self' ],
            end_document_h     => [ \&_end_document,   'self,line,column' ],
            start_h            => [ \&_start,          'self,tagname,line,column,@attr' ],
            end_h              => [ \&_end,            'self,tagname,line,column,tokenpos,@attr' ],
            text_h             => [ \&_text,           'self,text' ],
            strict_names       => 0,
            empty_element_tags => 1,
        );
    bless $self, $class;

    $self->{_gripe} = $gripe;
    $self->{_stack} = [];

    return $self;
}

sub gripe {
    my $self = shift;

    return $self->{_gripe}->( @_ );
}

sub _start_document {
}

sub _end_document {
    my ($self,$line,$column) = @_;

    for my $tag ( keys %isRequired ) {
        if ( !$self->{_first_seen}->{$tag} ) {
            $self->gripe( 'doc-tag-required', tag => $tag );
        }
    }

    return;
}

sub _start {
    my ($self,$tag,$line,$column,@attr) = @_;

    $self->{_line} = $line;
    $self->{_column} = $column;

    my $validattr = $isKnownAttribute{ $tag };
    if ( $validattr ) {
        my %seen;
        my $i = 0;
        while ( $i < @attr ) {
            my ($attr,$val) = @attr[$i++,$i++];
            if ( $seen{$attr}++ ) {
                $self->gripe( 'attr-repeated', tag => $tag, attr => $attr );
            }

            if ( $validattr && ( !$validattr->{$attr} ) ) {
                $self->gripe( 'attr-unknown', tag => $tag, attr => $attr );
            }
        } # while attribs
    }
    else {
        $self->gripe( 'elem-unknown', tag => $tag );
    }
    $self->_element_push( $tag ) unless $HTML::Tagset::emptyElement{ $tag };

    if ( my $where = $self->{_first_seen}{$tag} ) {
        if ( $isNonrepeatable{$tag} ) {
            $self->gripe( 'elem-nonrepeatable',
                            tag => $tag,
                            where => HTML::Lint::Error::where( @{$where} )
                        );
        }
    }
    else {
        $self->{_first_seen}{$tag} = [$line,$column];
    }

    # Call any other overloaded func
    my $tagfunc = "_start_$tag";
    if ( $self->can($tagfunc) ) {
        $self->$tagfunc( $tag, @attr );
    }

    return;
}

sub _text {
    my ($self,$text) = @_;

    while ( $text =~ /&(?![#0-9a-z])/ig ) {
        $self->gripe( 'text-use-entity', char => '&', entity => '&amp;' );
    }

    while ( $text =~ /([^\x09\x0A\x0D -~])/g ) {
        my $bad = $1;
        $self->gripe(
            'text-use-entity',
                char => sprintf( '\x%02lX', ord($bad) ),
                entity => $char2entity{ $bad },
        );
    }

    if ( not $self->{_unclosed_entities_regex} ) {
        # Get Gisle's list
        my @entities = sort keys %HTML::Entities::entity2char;

        # Strip his semicolons
        s/;$// for @entities;

        # Build a regex
        my $entities = join( '|', @entities );
        $self->{_unclosed_entities_regex} = qr/&($entities)(?!;)/;

        $self->{_entity_lookup} = { map { ($_,1) } @entities };
    }

    while ( $text =~ m/$self->{_unclosed_entities_regex}/g ) {
        my $ent = $1;
        $self->gripe( 'text-unclosed-entity', entity => "&$ent;" );
    }

    while ( $text =~ m/&([^;]+);/g ) {
        my $ent = $1;

        # Numeric entities are fine, if they're not too large.
        if ( $ent =~ /^#(\d+)$/ ) {
            if ( $1 > 65536 ) {
                $self->gripe( 'text-invalid-entity', entity => "&$ent;" );
            }
            next;
        }

        # Hex entities are fine, if they're not too large.
        if ( $ent =~ /^#x([\dA-F]+)$/i ) {
            if ( length($1) > 4 ) {
                $self->gripe( 'text-invalid-entity', entity => "&$ent;" );
            }
            next;
        }

        # If it's not a numeric entity, then check the lookup table.
        if ( !exists $self->{_entity_lookup}{$ent} ) {
            $self->gripe( 'text-unknown-entity', entity => "&$ent;" );
        }
    }

    return;
}

sub _end {
    my ($self,$tag,$line,$column,$tokenpos,@attr) = @_;

    $self->{_line} = $line;
    $self->{_column} = $column;

    if ( !$tokenpos ) {
        # This is a dummy end event for something like <img />.
        # Do nothing.
    }
    elsif ( $HTML::Tagset::emptyElement{ $tag } ) {
        $self->gripe( 'elem-empty-but-closed', tag => $tag );
    }
    else {
        if ( $self->_in_context($tag) ) {
            my @leftovers = $self->_element_pop_back_to($tag);
            for ( @leftovers ) {
                my ($tag,$line,$col) = @{$_};
                $self->gripe( 'elem-unclosed', tag => $tag,
                        where => HTML::Lint::Error::where($line,$col) )
                        unless $HTML::Tagset::optionalEndTag{$tag};
            } # for
        }
        else {
            $self->gripe( 'elem-unopened', tag => $tag );
        }
    } # is empty element

    # Call any other overloaded func
    my $tagfunc = "_end_$tag";
    if ( $self->can($tagfunc) ) {
        $self->$tagfunc( $tag, $line );
    }

    return;
}

sub _element_push {
    my $self = shift;
    for ( @_ ) {
        push( @{$self->{_stack}}, [$_,$self->{_line},$self->{_column}] );
    } # while

    return;
}

sub _find_tag_in_stack {
    my $self = shift;
    my $tag = shift;
    my $stack = $self->{_stack};

    my $offset = @{$stack} - 1;
    while ( $offset >= 0 ) {
        if ( $stack->[$offset][0] eq $tag ) {
            return $offset;
        }
        --$offset;
    } # while

    return;
}

sub _element_pop_back_to {
    my $self = shift;
    my $tag = shift;

    my $offset = $self->_find_tag_in_stack($tag) or return;

    my @leftovers = splice( @{$self->{_stack}}, $offset + 1 );
    pop @{$self->{_stack}};

    return @leftovers;
}

sub _in_context {
    my $self = shift;
    my $tag = shift;

    my $offset = $self->_find_tag_in_stack($tag);
    return defined $offset;
}

# Overridden tag-specific stuff
sub _start_img {
    my ($self,$tag,%attr) = @_;

    my ($h,$w,$src) = @attr{qw( height width src )};
    if ( defined $h && defined $w ) {
        # Check sizes
    }
    else {
        $self->gripe( 'elem-img-sizes-missing', src=>$src );
    }
    if ( not defined $attr{alt} ) {
        $self->gripe( 'elem-img-alt-missing', src=>$src );
    }

    return;
}

=head1 BUGS, WISHES AND CORRESPONDENCE

All bugs and requests are now being handled through GitHub.

    https://github.com/petdance/html-lint/issues

DO NOT send bug reports to http://rt.cpan.org/ or http://code.google.com/

=head1 TODO

=over 4

=item * Check for attributes that require values

=item * <TABLE>s that have no rows.

=item * Form fields that aren't in a FORM

=item * Check for valid entities, and that they end with semicolons

=item * DIVs with nothing in them.

=item * HEIGHT= that have percents in them.

=item * Check for goofy stuff like:

    <b><li></b><b>Hello Reader - Spanish Level 1 (K-3)</b>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2005-2012 Andy Lester.

This program is free software; you can redistribute it and/or modify
it under the terms of the Artistic License v2.0.

http://www.opensource.org/licenses/Artistic-2.0

Please note that these modules are not products of or supported by the
employers of the various contributors to the code.

=head1 AUTHOR

Andy Lester, andy at petdance.com

=cut

1;
