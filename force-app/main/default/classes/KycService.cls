/**
 * Service layer: KYC-style verification for Accounts and their financial accounts.
 * Reads only through selectors, writes only through a unit of work, so the
 * whole method is one atomic transaction and fully mockable.
 */
public with sharing class KycService implements IKycService {

    @TestVisible
    private static final Set<String> HIGH_RISK_COUNTRIES = new Set<String>{ 'Iran', 'North Korea', 'Syria', 'Myanmar' };
    @TestVisible
    private static final Decimal HIGH_BALANCE_THRESHOLD = 1000000;

    public class KycResult {
        public Id accountId;
        public String status;       // Passed | Manual Review | Failed
        public String riskRating;   // Low | Medium | High
        public List<String> reasons = new List<String>();
    }

    public List<KycResult> verify(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new KycVerificationException('At least one Account Id is required.');
        }
        IAccountsSelector accounts = (IAccountsSelector) Application.get(IAccountsSelector.class);
        IFinancialAccountsSelector finAccounts = (IFinancialAccountsSelector) Application.get(IFinancialAccountsSelector.class);

        Map<Id, Account> accountsById = new Map<Id, Account>(accounts.selectByIds(accountIds));
        Map<Id, List<Financial_Account__c>> faByAccount =
            new FinancialAccounts(finAccounts.selectByAccountIds(accountIds)).byAccount();

        IUnitOfWork uow = Application.newUnitOfWork();
        List<KycResult> results = new List<KycResult>();

        for (Id accountId : accountIds) {
            Account acc = accountsById.get(accountId);
            List<Financial_Account__c> fas = faByAccount.containsKey(accountId)
                ? faByAccount.get(accountId) : new List<Financial_Account__c>();
            KycResult r = evaluate(accountId, acc, fas);
            results.add(r);

            if (acc == null) {
                continue; // nothing to write against an inaccessible account
            }
            uow.registerNew(new KYC_Verification__c(
                Account__c = accountId,
                Status__c = r.status,
                Risk_Rating__c = r.riskRating,
                Reasons__c = String.join(r.reasons, '\n'),
                Verified_On__c = System.now()
            ));
            if (r.status == 'Failed') {
                for (Financial_Account__c fa : fas) {
                    if (fa.Status__c == 'Active') {
                        uow.registerDirty(new Financial_Account__c(Id = fa.Id, Status__c = 'Frozen'));
                    }
                }
            }
        }
        uow.commitWork();
        return results;
    }

    @TestVisible
    private static KycResult evaluate(Id accountId, Account acc, List<Financial_Account__c> fas) {
        KycResult r = new KycResult();
        r.accountId = accountId;
        r.riskRating = 'Low';
        if (acc == null) {
            r.status = 'Failed';
            r.reasons.add('Account not found or not accessible.');
            return r;
        }
        if (String.isBlank(acc.BillingCountry) || String.isBlank(acc.BillingStreet)) {
            r.reasons.add('Missing residential address.');
        }
        if (fas.isEmpty()) {
            r.reasons.add('No financial accounts on file.');
        }
        Decimal balance = new FinancialAccounts(fas).totalBalance();
        if (balance >= HIGH_BALANCE_THRESHOLD) {
            r.riskRating = 'Medium';
            r.reasons.add('Aggregate balance above ' + HIGH_BALANCE_THRESHOLD.format() + '.');
        }
        if (HIGH_RISK_COUNTRIES.contains(acc.BillingCountry)) {
            r.riskRating = 'High';
            r.reasons.add('High-risk jurisdiction: ' + acc.BillingCountry + '.');
        }

        if (r.reasons.contains('Missing residential address.')) {
            r.status = 'Failed';
        } else if (r.riskRating == 'High' || fas.isEmpty()) {
            r.status = 'Manual Review';
        } else {
            r.status = 'Passed';
        }
        return r;
    }
}
