# Ix
## Instant JMAP Interface

> **ACHTUNG**
>
> Ix is highly experimental, or at least under pretty active development, with
> no guarantees about backward compatibility.  It might change radically
> overnight, and if you were relying on it not to do that, *you are going to
> have a bad time*.

Ix is a framework for building applications using the [JMAP](http://jmap.io/)
protocol.  Ix provides abstractions for writing method handlers to handle
JMAP requests containing multiple method calls.  It also provides a mapping
layer to automatically provide JMAP's CRUD and windows query interfaces by
mapping to a DBIx::Class schema.

Ix doesn't have documentation, but it has decent tests.  It's also much more
heavily tested than it appears, because there are test suites for internal
products built on Ix.  Remember, though:  because Ix is being changed as much
as we want, whenever we want, you can't use the tests as promises of what will
stay the same.  If we change the framework, we'll just change the tests, too.

To play with Ix, you'll need to install the prereqs that Dist::Zilla will
compute, including at least one that's not on the CPAN:
[Test::PgMonger](https://github.com/fastmail/Test-PgMonger).  You'll also need
a working PostgreSQL install.
