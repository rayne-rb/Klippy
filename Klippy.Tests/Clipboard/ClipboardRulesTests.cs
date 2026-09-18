using System.Text;
using Klippy.Server.Features.Clipboard;
using Klippy.Shared.Clipboard;
using Xunit;

namespace Klippy.Tests.Clipboard;

/// <summary>
/// The clipboard's rules, checked without a database behind them: who may read an entry,
/// and what the server will accept as one.
/// </summary>
public sealed class ClipboardRulesTests
{
    private static readonly Guid Tulonga = Guid.NewGuid();
    private static readonly Guid Sam = Guid.NewGuid();

    [Fact]
    public void An_account_can_read_its_own_entries()
    {
        var entry = Entry(Tulonga, ClipboardVisibility.Group);

        Assert.True(ClipboardService.CanRead(entry, Tulonga));
    }

    [Fact]
    public void A_group_entry_is_invisible_to_every_other_account()
    {
        var entry = Entry(Tulonga, ClipboardVisibility.Group);

        Assert.False(ClipboardService.CanRead(entry, Sam));

        // And to a device nobody has approved into an account at all.
        Assert.False(ClipboardService.CanRead(entry, null));
    }

    [Fact]
    public void A_server_entry_is_visible_to_everyone()
    {
        var entry = Entry(Tulonga, ClipboardVisibility.Server);

        Assert.True(ClipboardService.CanRead(entry, Sam));
        Assert.True(ClipboardService.CanRead(entry, Tulonga));
        Assert.True(ClipboardService.CanRead(entry, null));
    }

    [Fact]
    public void Text_within_the_cap_is_accepted()
    {
        Assert.Null(ClipboardService.DescribeTextProblem("a perfectly ordinary copy"));
    }

    [Fact]
    public void Empty_text_is_refused()
    {
        Assert.NotNull(ClipboardService.DescribeTextProblem(""));
        Assert.NotNull(ClipboardService.DescribeTextProblem(null));
    }

    [Fact]
    public void Text_past_the_cap_is_refused_by_bytes_not_characters()
    {
        // Every one of these is three bytes in UTF-8, so a cap counted in characters
        // would let through three times what it means to.
        var justOver = new string('中', (ClipboardLimits.MaxTextBytes / 3) + 1);

        Assert.True(justOver.Length < ClipboardLimits.MaxTextBytes);
        Assert.True(Encoding.UTF8.GetByteCount(justOver) > ClipboardLimits.MaxTextBytes);
        Assert.NotNull(ClipboardService.DescribeTextProblem(justOver));
    }

    [Fact]
    public void An_image_must_actually_be_a_png()
    {
        Assert.Null(ClipboardService.DescribeImageProblem(Png()));
        Assert.NotNull(ClipboardService.DescribeImageProblem(Encoding.UTF8.GetBytes("not a png at all")));
        Assert.NotNull(ClipboardService.DescribeImageProblem([]));
    }

    [Fact]
    public void An_image_past_the_cap_is_refused()
    {
        var huge = Png(ClipboardLimits.MaxImageBytes + 1);

        Assert.NotNull(ClipboardService.DescribeImageProblem(huge));
    }

    [Fact]
    public void A_truncated_png_header_is_not_a_png()
    {
        // Eight bytes of signature and nothing after it: long enough to look right to a
        // check that only counts, which is why the check does not only count.
        Assert.False(ClipboardService.LooksLikePng([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
    }

    [Fact]
    public void The_digest_is_the_same_for_the_same_bytes_and_different_otherwise()
    {
        var once = ClipboardService.Digest("the same thing"u8.ToArray());
        var again = ClipboardService.Digest("the same thing"u8.ToArray());
        var other = ClipboardService.Digest("something else"u8.ToArray());

        // This is what stops a polled clipboard filling the board with one entry over and
        // over, and what lets a device tell its own writes apart from a fresh copy.
        Assert.Equal(once, again);
        Assert.NotEqual(once, other);
        Assert.Equal(64, once.Length);
    }

    private static ClipboardEntryRow Entry(Guid owner, string visibility) => new()
    {
        EntryId = Guid.NewGuid(),
        OwnerUserId = owner,
        SourceDeviceId = Guid.NewGuid(),
        Visibility = visibility,
        ContentType = ClipboardContentTypes.Text,
        ContentText = "something copied",
        ByteSize = 16,
        Digest = "irrelevant",
        CopiedAt = DateTimeOffset.UtcNow,
    };

    /// <summary>A byte array that starts like a PNG, padded to <paramref name="size"/>.</summary>
    private static byte[] Png(int size = 32)
    {
        var bytes = new byte[size];
        ReadOnlySpan<byte> signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        signature.CopyTo(bytes);
        return bytes;
    }
}
