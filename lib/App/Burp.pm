package App::Burp;

use 5.010001;
use strictures;
use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 11 $ =~ /\d+/gmx );

use Class::Usul::Functions  qw( ns_environment );

sub env_var {
   return ns_environment __PACKAGE__, $_[1], $_[2];
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Burp - Watch for changes to files and run commands

=head1 Synopsis

   use App::Burp;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines no attributes

=head1 Subroutines/Methods

=head2 C<env_var>

   $value = App::Burp->env_var( 'name', 'new_value' );

Looks up the environment variable and returns it's value. Also acts as a
mutator if provided with an optional new value. Uppercases and prefixes
the environment variable key

=head1 Diagnostics

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Burp.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2016 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
