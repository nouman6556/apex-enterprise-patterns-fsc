/** End-to-end tests with real selectors, trigger, unit of work and async jobs. */
@IsTest
private class IntegrationTest {

    private static User kycUser() {
        return TestUsers.withPermissionSet('KYC_Operations');
    }

    /** Seed synthetic data as the running user so user-mode sharing and FLS apply. */
    private static void seed() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Synthetic Household A', BillingStreet = '1 Main St', BillingCountry = 'United States'),
            new Account(Name = 'Synthetic Household B', BillingCountry = null)
        };
        insert accounts;
        insert new List<Financial_Account__c>{
            new Financial_Account__c(Account__c = accounts[0].Id, Account_Number__c = '10000001', Type__c = 'Checking', Balance__c = 1500),
            new Financial_Account__c(Account__c = accounts[1].Id, Account_Number__c = '10000002', Type__c = 'Savings', Balance__c = 300)
        };
    }

    @IsTest
    static void domainAppliesDefaultsAndValidates() {
        System.runAs(kycUser()) {
            seed();
            Financial_Account__c fa = [SELECT Status__c FROM Financial_Account__c LIMIT 1];
            Assert.areEqual('Active', fa.Status__c, 'Default status applied by domain');

            Account a = [SELECT Id FROM Account LIMIT 1];
            Database.SaveResult bad = Database.insert(new Financial_Account__c(
                Account__c = a.Id, Account_Number__c = 'ABC', Type__c = 'Savings', Balance__c = -10), false);
            Assert.isFalse(bad.isSuccess());
            Assert.areEqual(2, bad.getErrors().size(), 'Both validation rules fire');

            Database.SaveResult card = Database.insert(new Financial_Account__c(
                Account__c = a.Id, Account_Number__c = '4000000000', Type__c = 'Credit Card', Balance__c = -250), false);
            Assert.isTrue(card.isSuccess(), 'Credit cards may be negative');
        }
    }

    @IsTest
    static void unitOfWorkResolvesParentsAndCommitsInOrder() {
        System.runAs(kycUser()) {
            seed();
            IUnitOfWork uow = Application.newUnitOfWork();
            Account parent = new Account(Name = 'Synthetic New Household', BillingStreet = '9 Elm St', BillingCountry = 'Canada');
            uow.registerNew(parent);
            Financial_Account__c child = new Financial_Account__c(Account_Number__c = '20000001', Type__c = 'Brokerage', Balance__c = 10);
            uow.registerNew(child, Financial_Account__c.Account__c, parent);
            uow.commitWork();

            Assert.isNotNull(parent.Id);
            Assert.areEqual(parent.Id, [SELECT Account__c FROM Financial_Account__c WHERE Id = :child.Id].Account__c);
        }
    }

    @IsTest
    static void unitOfWorkRollsBackEverythingOnFailure() {
        System.runAs(kycUser()) {
            seed();
            Integer before = [SELECT COUNT() FROM Account];
            IUnitOfWork uow = Application.newUnitOfWork();
            Account parent = new Account(Name = 'Synthetic Rollback');
            uow.registerNew(parent);
            uow.registerNew(new Financial_Account__c(Account_Number__c = 'bad', Type__c = 'Savings'),
                Financial_Account__c.Account__c, parent);
            try {
                uow.commitWork();
                Assert.fail('Expected UnitOfWorkException');
            } catch (UnitOfWorkException e) {
                Assert.areEqual(before, [SELECT COUNT() FROM Account], 'Parent insert was rolled back');
            }
        }
    }

    @IsTest
    static void unitOfWorkGuardsAgainstMisuse() {
        System.runAs(kycUser()) {
            seed();
            IUnitOfWork uow = new UnitOfWork(new List<Schema.SObjectType>{ Account.SObjectType });
            try {
                uow.registerNew(new Contact(LastName = 'x'));
                Assert.fail('Unregistered type should throw');
            } catch (UnitOfWorkException e) {
                Assert.isTrue(e.getMessage().contains('not registered'));
            }
            try {
                uow.registerDirty(new Account(Name = 'no id'));
                Assert.fail('Dirty without Id should throw');
            } catch (UnitOfWorkException e) {
                Assert.isTrue(e.getMessage().contains('Id'));
            }
        }
    }

    @IsTest
    static void queueableVerifiesAndFreezesFailedAccounts() {
        System.runAs(kycUser()) {
            seed();
            List<Id> ids = new List<Id>(new Map<Id, Account>([SELECT Id FROM Account]).keySet());
            KycVerificationQueueable job = new KycVerificationQueueable(ids, 1);
            Test.startTest();
            System.enqueueJob(job);
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM KYC_Verification__c], 'First chunk of size 1 processed');
            Assert.areEqual(2, job.pendingCount());
        }
    }

    @IsTest
    static void batchReverifiesActiveAccounts() {
        System.runAs(kycUser()) {
            seed();
            Test.startTest();
            Database.executeBatch(new KycReverificationBatch(), 200);
            Test.stopTest();

            Assert.areEqual(2, [SELECT COUNT() FROM KYC_Verification__c]);
            Account noAddress = [SELECT Id FROM Account WHERE BillingCountry = null LIMIT 1];
            Assert.areEqual('Failed', [SELECT Status__c FROM KYC_Verification__c WHERE Account__c = :noAddress.Id].Status__c);
            Assert.areEqual('Frozen', [SELECT Status__c FROM Financial_Account__c WHERE Account__c = :noAddress.Id].Status__c);
        }
    }

    @IsTest
    static void schedulerStartsBatch() {
        Test.startTest();
        String jobId = System.schedule('KYC test schedule', '0 0 2 * * ?', new KycReverificationBatch());
        Test.stopTest();
        Assert.isNotNull(jobId);
        Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId]);
    }
}
