using System.Security.Cryptography;
using System.Text;

namespace Klippy.Server.Features.Pairing;

/// <summary>Token and code generation. Kept apart so the rules are visible in one place.</summary>
public static class PairingTokens
{
    /// <summary>
    /// No I, O, 0 or 1: the code gets read off one screen and compared against another,
    /// so the characters people confuse are simply not in the alphabet.
    /// </summary>
    private const string CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    private const int CodeLength = 6;

    public static string NewCode()
    {
        var chars = new char[CodeLength];
        for (var i = 0; i < CodeLength; i++)
        {
            chars[i] = CodeAlphabet[RandomNumberGenerator.GetInt32(CodeAlphabet.Length)];
        }

        return new string(chars);
    }

    /// <summary>256 bits, URL-safe so it can ride in a query string on the WebSocket upgrade.</summary>
    public static string NewToken() =>
        Base64UrlEncode(RandomNumberGenerator.GetBytes(32));

    /// <summary>What actually gets stored. The plaintext token is handed to the device once and then dropped.</summary>
    public static string Hash(string token) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
