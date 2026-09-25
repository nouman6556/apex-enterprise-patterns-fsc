/**
 * Domain class for Financial_Account__c: validation, defaults and
 * aggregate calculations. Works on in-memory lists, so it is used both by
 * the trigger and by services (without any extra queries).
 */
public with sharing class FinancialAccounts {

    private static final Pattern ACCOUNT_NUMBER = Pattern.compile('^[0-9]{8,12}$');
    private final List<Financial_Account__c> records;

    public FinancialAccounts(List<Financial_Account__c> records) {
        this.records = records == null ? new List<Financial_Account__c>() : records;
    }

    public void onBeforeInsert() {
        applyDefaults();
        validate();
    }

    public void onBeforeUpdate() {
        validate();
    }

    public void applyDefaults() {
        for (Financial_Account__c fa : records) {
            if (fa.Status__c == null) { fa.Status__c = 'Active'; }
            if (fa.Balance__c == null) { fa.Balance__c = 0; }
        }
    }

    public void validate() {
        for (Financial_Account__c fa : records) {
            if (fa.Account_Number__c == null || !ACCOUNT_NUMBER.matcher(fa.Account_Number__c).matches()) {
                fa.addError(Financial_Account__c.Account_Number__c, 'Account number must be 8-12 digits.');
            }
            if (fa.Balance__c != null && fa.Balance__c < 0 && fa.Type__c != 'Credit Card') {
                fa.addError(Financial_Account__c.Balance__c, 'Only credit card accounts can carry a negative balance.');
            }
        }
    }

    public Map<Id, List<Financial_Account__c>> byAccount() {
        Map<Id, List<Financial_Account__c>> result = new Map<Id, List<Financial_Account__c>>();
        for (Financial_Account__c fa : records) {
            if (!result.containsKey(fa.Account__c)) {
                result.put(fa.Account__c, new List<Financial_Account__c>());
            }
            result.get(fa.Account__c).add(fa);
        }
        return result;
    }

    public Decimal totalBalance() {
        Decimal total = 0;
        for (Financial_Account__c fa : records) {
            total += fa.Balance__c == null ? 0 : fa.Balance__c;
        }
        return total;
    }
}
