/**
 * Pure unit tests: selectors and the unit of work are replaced with
 * in-memory fakes, so these tests issue no SOQL and no DML at all.
 */
@IsTest
private class KycServiceTest {

    private static Integer idCounter = 1;

    private static Id fakeId(Schema.SObjectType t) {
        String n = String.valueOf(idCounter++);
        return Id.valueOf(t.getDescribe().getKeyPrefix() + '0'.repeat(12 - n.length()) + n);
    }

    private class FakeAccounts implements IAccountsSelector {
        List<Account> rows = new List<Account>();
        public List<Account> selectByIds(Set<Id> ids) {
            List<Account> out = new List<Account>();
            for (Account a : rows) { if (ids.contains(a.Id)) { out.add(a); } }
            return out;
        }
    }

    private class FakeFinancialAccounts implements IFinancialAccountsSelector {
        List<Financial_Account__c> rows = new List<Financial_Account__c>();
        public List<Financial_Account__c> selectByAccountIds(Set<Id> ids) {
            List<Financial_Account__c> out = new List<Financial_Account__c>();
            for (Financial_Account__c fa : rows) { if (ids.contains(fa.Account__c)) { out.add(fa); } }
            return out;
        }
    }

    private class FakeUnitOfWork implements IUnitOfWork {
        List<SObject> inserted = new List<SObject>();
        List<SObject> updated = new List<SObject>();
        Integer commits = 0;
        public void registerNew(SObject r) { inserted.add(r); }
        public void registerNew(SObject r, Schema.SObjectField f, SObject parent) { inserted.add(r); }
        public void registerDirty(SObject r) { updated.add(r); }
        public void registerDeleted(SObject r) { updated.add(r); }
        public void commitWork() { commits++; }
    }

    private static FakeAccounts accounts = new FakeAccounts();
    private static FakeFinancialAccounts finAccounts = new FakeFinancialAccounts();
    private static FakeUnitOfWork uow = new FakeUnitOfWork();

    private static Account account(String country) {
        Account a = new Account(Id = fakeId(Account.SObjectType), Name = 'Synthetic ' + idCounter,
            BillingCountry = country, BillingStreet = country == null ? null : '1 Test St');
        accounts.rows.add(a);
        return a;
    }

    private static Financial_Account__c finAccount(Id accountId, Decimal balance) {
        Financial_Account__c fa = new Financial_Account__c(Id = fakeId(Financial_Account__c.SObjectType),
            Account__c = accountId, Balance__c = balance, Status__c = 'Active', Type__c = 'Checking',
            Account_Number__c = '12345678');
        finAccounts.rows.add(fa);
        return fa;
    }

    private static void wire() {
        Application.setMock(IAccountsSelector.class, accounts);
        Application.setMock(IFinancialAccountsSelector.class, finAccounts);
        Application.setMockUnitOfWork(uow);
    }

    @IsTest
    static void verifiesWithoutTouchingTheDatabase() {
        Account ok = account('United States');
        finAccount(ok.Id, 25000);
        Account rich = account('Canada');
        finAccount(rich.Id, 900000);
        finAccount(rich.Id, 200000);
        Account risky = account('Syria');
        finAccount(risky.Id, 100);
        Account noAddress = account(null);
        Financial_Account__c toFreeze = finAccount(noAddress.Id, 50);
        wire();

        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        Map<Id, KycService.KycResult> byId = new Map<Id, KycService.KycResult>();
        for (KycService.KycResult r : new KycService().verify(new Set<Id>{ ok.Id, rich.Id, risky.Id, noAddress.Id })) {
            byId.put(r.accountId, r);
        }

        Assert.areEqual(queriesBefore, Limits.getQueries(), 'Service tests must not query');
        Assert.areEqual(dmlBefore, Limits.getDmlStatements(), 'Service tests must not perform DML');

        Assert.areEqual('Passed', byId.get(ok.Id).status);
        Assert.areEqual('Low', byId.get(ok.Id).riskRating);
        Assert.areEqual('Medium', byId.get(rich.Id).riskRating);
        Assert.areEqual('Manual Review', byId.get(risky.Id).status);
        Assert.areEqual('High', byId.get(risky.Id).riskRating);
        Assert.areEqual('Failed', byId.get(noAddress.Id).status);

        Assert.areEqual(1, uow.commits, 'Exactly one atomic commit');
        Assert.areEqual(4, uow.inserted.size(), 'One KYC_Verification__c per account');
        Assert.areEqual(1, uow.updated.size(), 'Failed account financial accounts are frozen');
        Assert.areEqual(toFreeze.Id, uow.updated[0].Id);
        Assert.areEqual('Frozen', ((Financial_Account__c) uow.updated[0]).Status__c);
    }

    @IsTest
    static void missingAccountFailsWithoutWriting() {
        wire();
        Id ghost = fakeId(Account.SObjectType);
        List<KycService.KycResult> results = new KycService().verify(new Set<Id>{ ghost });
        Assert.areEqual('Failed', results[0].status);
        Assert.areEqual(0, uow.inserted.size());
    }

    @IsTest
    static void accountWithoutFinancialAccountsNeedsReview() {
        Account a = account('United States');
        wire();
        Assert.areEqual('Manual Review', new KycService().verify(new Set<Id>{ a.Id })[0].status);
    }

    @IsTest
    static void emptyRequestThrows() {
        try {
            new KycService().verify(new Set<Id>());
            Assert.fail('Expected KycVerificationException');
        } catch (KycVerificationException e) {
            Assert.isInstanceOfType(e, FscException.class, 'Part of the FscException hierarchy');
        }
    }
}
