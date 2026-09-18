using Klippy.Server.Features.Accounts;
using Xunit;

namespace Klippy.Tests.Accounts;

/// <summary>
/// The account rules that hold without a database behind them: what a role may be, and
/// what a password may be changed to.
/// </summary>
public sealed class AccountRulesTests
{
    [Fact]
    public void There_are_two_roles_and_a_new_account_is_offered_the_lesser_one_first()
    {
        Assert.Equal([KlippyRoles.User, KlippyRoles.Admin], KlippyRoles.All);

        // Order matters on the screen: a picker that opens on "admin" is a picker that
        // hands out admin by accident.
        Assert.Equal(KlippyRoles.User, KlippyRoles.All[0]);
    }

    [Theory]
    [InlineData("admin")]
    [InlineData("user")]
    public void A_known_role_is_accepted(string role) => Assert.True(KlippyRoles.IsKnown(role));

    [Theory]
    [InlineData("Admin")]
    [InlineData("root")]
    [InlineData("")]
    [InlineData(null)]
    public void Anything_else_is_not_a_role(string? role) => Assert.False(KlippyRoles.IsKnown(role));

    [Fact]
    public void Every_role_says_what_it_can_do()
    {
        // The picker shows this under the choice, so a blank one would be a choice made
        // with nothing to go on.
        foreach (var role in KlippyRoles.All)
        {
            Assert.NotEmpty(KlippyRoles.Describe(role));
        }
    }

    [Fact]
    public void A_new_password_has_to_be_typed_the_same_twice() =>
        Assert.NotNull(AccountService.DescribeNewPasswordProblem("old-one", "new-one-here", "new-two-here"));

    [Fact]
    public void A_new_password_has_to_be_long_enough() =>
        Assert.NotNull(AccountService.DescribeNewPasswordProblem("old-one", "short", "short"));

    [Fact]
    public void A_new_password_has_to_be_new() =>
        Assert.NotNull(AccountService.DescribeNewPasswordProblem("same-one-here", "same-one-here", "same-one-here"));

    [Fact]
    public void An_acceptable_change_has_nothing_wrong_with_it() =>
        Assert.Null(AccountService.DescribeNewPasswordProblem("old-one-here", "new-one-here", "new-one-here"));

    [Fact]
    public void The_length_is_counted_before_the_match_is_checked() =>
        // Both wrong at once should complain about the mismatch, which is the one the
        // person can see for themselves and fix without being told the rule.
        Assert.Equal(
            "The two new passwords are not the same.",
            AccountService.DescribeNewPasswordProblem("old", "abc", "xyz"));
}
