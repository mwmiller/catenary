# Catenary

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## What is it?

A local-first social network. It works on the machines you already have, on
the network you already have, and does not need the public internet to be
useful.

Underneath, it is a peer-to-peer feed reader and publishing platform. Each user
owns their identity (a cryptographic keypair) and their content (signed,
append-only logs). There is no account, and no service that holds, serves, or
can revoke anything you publish.

Two things live side by side in the same app: a social feed (journals, replies,
images, tags, reactions, mentions) and a turn-based backgammon game played
against people you are already connected to.

## Install

Installers are on each [GitHub release](https://github.com/mwmiller/catenary/releases):

* **macOS** (Apple Silicon) — `.dmg`, drag into Applications
* **Windows** (x86_64) — `.exe` installer
* **Linux** (x86_64) — `.deb`, `.rpm`, or `.AppImage`

There is currently no Intel Mac build.

## Getting started

Catenary gives you an identity on first launch — a keypair you own, stored
locally. Nothing to sign up for.

Out of the box you will not see anyone else's content, because you are not
connected to anyone yet. There are two ways in, and either one is enough.

**With internet access, use a bootstrap peer.** The address fields come
pre-filled with a well-known bootstrap peer. Connecting to it is a
convenience — it gets a fresh install moving without anyone having to hand
you an address, and you are not tied to it afterwards.

**Without internet access, use a peer you already have.** Enter any
`host:port` in those same fields. If someone near you is already running
Catenary, exchanging addresses with them is enough, and no service is
involved. On a local network, press *Scan for local peers* and Catenary lists
what it finds advertising itself as `_bushbaby._tcp` over mDNS.

Either way, entries are then exchanged directly between the two of you. The
peers you connect to are announced as **oases** and propagated through the
logs, so they become discoverable to everyone who talks to them — you will
not be the only one keeping track. That is why the first connection is the
only one you have to arrange yourself.

## Local-first

Everything Catenary needs is on your machine. The interface is built to run
with the network unplugged — no webfonts, no CDN, no remote assets — and the
backend is a process on your own computer that the desktop shell talks to over
loopback. The app renders and stores your content with no internet connection
at all.

What wide internet access buys you is reach and speed, not function. On a LAN,
peers find each other over mDNS and swap entries directly. With internet
access, the same peers replicate with distant ones faster and further. A node
that never leaves your network is a complete, working Catenary node — it just
has a smaller network to be complete about.

## What you can publish

Each kind of content lives in its own log, and you can enable or refuse them
individually:

| Content | What it is |
| --- | --- |
| Journal | Long-form posts on your profile |
| Reply | A response to someone else's entry |
| Image | JPEG, PNG, or GIF |
| Tag | Attach tags to entries you store |
| Reaction | Emoji reactions |
| Mention | Mention another identity |
| Graph | Block or unblock an identity |
| Challenge | A backgammon game |

**Backgammon** is the unusual one. Each player commits to a chain of random
values before the game starts, and each turn reveals the next pair. Because
each player's commitment is already fixed and published, neither side can
change the dice after seeing the opponent's roll. Moves are exchanged and
retained the same way posts are, so a game is a log like any other.

## How it works

Catenary peers find each other and exchange data directly — there is no
central server holding content. Once two nodes connect, they each say what
they have and what they want, and swap entries.

Because logs are independent, each node can choose exactly which types of
content to carry. A node can follow someone's journal but not their game
moves by blocking that content type — the node simply won't store or relay
it. Blocking works by content type, by author, or by entire families of
derived logs.

Multiple devices can share the same identity — a phone and a laptop each
write to their own slot within a content type. Other nodes see the combined
log as a single, coherent sequence.

A *bootstrap node* is a convenience. It gives a new install one well-known
peer to talk to, so the mesh is reachable from a cold start without anyone
having to hand you an address. Nothing is stored there, and content is not
routed through it — the two peers swap entries directly.

Long-term discovery does not depend on that bootstrap. Every peer a node
learns about is announced as an **oasis**, and those announcements travel in
the logs themselves, so a peer you connect to once becomes known to the peers
you connect to next, and to theirs. The bootstrap only has to get you into
the network; after that, the network introduces you.

The mesh protocol is **Bushbaby**. The spec lives in `Bushbaby.md` in the
`baby` repository, which is published to Hex as the `:baby` dependency and
developed in a sibling checkout alongside Catenary.

## Your data

Everything lives in one directory, `~/.catenary` by default. Set the
`CATENARY_HOME` environment variable to put it elsewhere.

**Back up that directory.** Your identity is a keypair held in it, and the
content you have collected is not recoverable from anywhere else — there is
no server-side copy by design. Copying the directory to another machine
carries your identity and your content with it.
