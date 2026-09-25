/**
 * Composition root / service locator.
 * Production code asks Application for an interface; tests swap in
 * in-memory implementations with setMock(), so service logic can be
 * tested with zero SOQL and zero DML.
 */
public inherited sharing class Application {

    private static final Map<System.Type, System.Type> BINDINGS = new Map<System.Type, System.Type>{
        IAccountsSelector.class          => AccountsSelector.class,
        IFinancialAccountsSelector.class => FinancialAccountsSelector.class,
        IKycService.class                => KycService.class
    };

    /** Parent-to-child commit order for every unit of work in this module. */
    public static final List<Schema.SObjectType> COMMIT_ORDER = new List<Schema.SObjectType>{
        Account.SObjectType, Financial_Account__c.SObjectType, KYC_Verification__c.SObjectType
    };

    private static final Map<System.Type, Object> MOCKS = new Map<System.Type, Object>();
    private static IUnitOfWork mockUnitOfWork;

    public static Object get(System.Type interfaceType) {
        if (MOCKS.containsKey(interfaceType)) {
            return MOCKS.get(interfaceType);
        }
        System.Type impl = BINDINGS.get(interfaceType);
        if (impl == null) {
            throw new FscException('No binding registered for ' + interfaceType);
        }
        return impl.newInstance();
    }

    public static IUnitOfWork newUnitOfWork() {
        return mockUnitOfWork != null ? mockUnitOfWork : new UnitOfWork(COMMIT_ORDER);
    }

    @TestVisible
    private static void setMock(System.Type interfaceType, Object implementation) {
        MOCKS.put(interfaceType, implementation);
    }

    @TestVisible
    private static void setMockUnitOfWork(IUnitOfWork uow) {
        mockUnitOfWork = uow;
    }
}
