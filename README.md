# ETrade CLI
A work-in-progress bash tool to utilize the ETrade developer's API. The tool was made as a way to find stocks that were candidates to sell put options for, and that is its initial primary function with the `calc` command. The `calc` command uses functionality that is also provided by the `quote` command, which can be used to retrieve stock and option quotes separate from `calc`. Retrieving quotes utilizes functionality provided by the `auth` command, which can be used on its own, to authorize access to the ETrade operations of the developer API.

## Use
### Authorization
In order to use this tool, you will need an ETrade account, and to have consumer keys to use for the OAuth protocol. Instructions for requesting key found at https://developer.etrade.com/getting-started. Keys are stored in gnome-keyring for the application's use with the `auth setup` command:

```console
$ ./etrade auth setup
Enter key for Etrade Account Key:
Password:
Enter key for Etrade Account Secret:
Password:
```

To obtain authorization, with `auth get`, `auth force`, or any `quote` operation, a link will be provided (and browser opened to the same url if default browser is set) for user to log in and authenticate. A code is provided to the user that must be pasted into the authorization prompt.

```console
$ ./etrade auth get
Requesting token

************************************
If browser page didn't load, go to:
https://us.etrade.com/e/t/etws/authorize?key=somekeyvalue&token=sometokenvalue
************************************

Input verification code:
```

### Put Option Calculation

The `calc put` command searches for put options expiring 'next Friday' (as determined by `date`) and finds puts with a bid price of >= 1% of the strike price, outputting the option with maximum spread/difference between that stock's price and the option strike price. See a simple example below, showing symbol, strike, bid, 'percent of strike', and the spread between strike and stock price. The command also generates a .csv file with header.

```console
$ ./etrade calc put
Enter stock symbols, separated by ',' ';' ' ' or newlines. Ctrl+d to complete:
AAOI CDE HL PAAS

AAOI  46.00 2.15 0.05  5.49
CDE   22.50 0.25 0.01  2.16
HL    22.00 0.32 0.01  2.04
PAAS  60.00 0.60 0.01  4.60
```

Results can be filtered to show only strike prices in a certain range:

```console
$ ./etrade calc put -m 40 -M 65
Enter stock symbols, separated by ',' ';' ' ' or newlines. Ctrl+d to complete:
AAOI CDE HL PAAS

AAOI  46.00 2.15 0.05  5.49
PAAS  60.00 0.60 0.01  4.60
```

And to only show options with spreads above a certain minimum:
```console
$ ./etrade calc put -m 40 -M 65 -d 5
Enter stock symbols, separated by ',' ';' ' ' or newlines. Ctrl+d to complete:
AAOI CDE HL PAAS

AAOI  46.00 2.15 0.05  5.49
```

The `-W|--weekly` option will retrieve all equities that have weekly expiring options from https://www.cboe.com/available_weeklys and perform operations for all possible weekly options.

The `calc` command will automatically perform quote retrieval if necessary. A local cache of json quote responses (see Quote Retrieval) can be used as input to the `calc` command with the `-r|--read-cache` option. Any of the `calc` input options will use quotes in the cache if they exist, but the `-r` option will only perform operations for those quotes that have been cached.

### Quote Retrieval

The `quote` command can be used directly to retrieve quotes independent from the `calc` command. By default, an individual `quote` or `quote option` command will print the json response to stdout. But with the `-w|-write-cache` option, or with use of the `quote batch` command, json responses are stored to files in a local cache.

The `calc` command can use the cached quotes, but the `quote` command can also be used to read the quote from the cache back to stdout with the `-r|--read-cache` option.

Similar to the `calc` command, `quote batch` has a `-W|--weekly` option to get quotes for all equities that have weekly expiring options.

## Installation

Not yet. To date only run in place.

The tool makes use of the Linux keyring with `keyctl`, Gnome-keyring using `secret-tool`, `curl` and `jq` which all must be available.

## License

[Unlicense](https://unlicense.org)