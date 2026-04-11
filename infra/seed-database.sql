-- ──────────────────────────────────────────────────────────────
--  Zava — Seed Database
--  Creates tables and inserts demo data for the SRE Agent lab
-- ──────────────────────────────────────────────────────────────

-- ── Products ────────────────────────────────────────────────

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Products')
BEGIN
    CREATE TABLE Products (
        Id          INT IDENTITY(1,1) PRIMARY KEY,
        Name        NVARCHAR(200)   NOT NULL,
        Price       DECIMAL(10,2)   NOT NULL,
        Category    NVARCHAR(100)   NOT NULL,
        CreatedAt   DATETIME2       DEFAULT GETUTCDATE()
    );
END;
GO

-- ── Orders ──────────────────────────────────────────────────

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Orders')
BEGIN
    CREATE TABLE Orders (
        Id              INT IDENTITY(1,1) PRIMARY KEY,
        CustomerName    NVARCHAR(200)   NOT NULL,
        CustomerEmail   NVARCHAR(200)   NOT NULL,
        OrderDate       DATETIME2       DEFAULT GETUTCDATE(),
        Status          NVARCHAR(50)    DEFAULT 'Pending',
        TotalAmount     DECIMAL(10,2)   NOT NULL
    );
END;
GO

-- ── OrderItems ──────────────────────────────────────────────

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'OrderItems')
BEGIN
    CREATE TABLE OrderItems (
        Id          INT IDENTITY(1,1) PRIMARY KEY,
        OrderId     INT             NOT NULL,
        ProductId   INT             NOT NULL,
        Quantity    INT             NOT NULL DEFAULT 1,
        UnitPrice   DECIMAL(10,2)   NOT NULL,
        CONSTRAINT FK_OrderItems_Orders   FOREIGN KEY (OrderId)   REFERENCES Orders(Id),
        CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductId) REFERENCES Products(Id)
    );
END;
GO

-- ── Seed Products ───────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM Products)
BEGIN
    INSERT INTO Products (Name, Price, Category) VALUES
    -- Running
    ('Zava UltraBoost Running Shoe',          149.99, 'Running'),
    ('Zava AirStride Marathon Shoe',           179.99, 'Running'),
    ('Zava TrailBlazer Off-Road Shoe',         139.99, 'Running'),
    ('Zava SpeedLite Racing Flat',             159.99, 'Running'),
    ('Zava CloudRun Daily Trainer',            124.99, 'Running'),
    -- Training
    ('Zava FlexFit Training Shoe',             109.99, 'Training'),
    ('Zava PowerLift Gym Shoe',                129.99, 'Training'),
    ('Zava AgilityPro Cross-Trainer',          119.99, 'Training'),
    -- Apparel
    ('Zava DryFit Performance Tee',             49.99, 'Apparel'),
    ('Zava ThermoRun Winter Jacket',           129.99, 'Apparel'),
    ('Zava BreezeLite Running Shorts',          44.99, 'Apparel'),
    ('Zava CompressionPro Tights',              69.99, 'Apparel'),
    ('Zava StormShield Rain Jacket',            99.99, 'Apparel'),
    ('Zava UltraLight Tank Top',                39.99, 'Apparel'),
    -- Accessories
    ('Zava HydroFlask 32oz Bottle',             34.99, 'Accessories'),
    ('Zava ProGrip Running Gloves',             29.99, 'Accessories'),
    ('Zava VisioSport Sunglasses',              89.99, 'Accessories'),
    ('Zava PaceSetter GPS Watch',              249.99, 'Accessories'),
    ('Zava ComfortPlus Insoles',                24.99, 'Accessories'),
    ('Zava ReflectRun Safety Vest',             44.99, 'Accessories');
END;
GO

-- ── Seed Orders ─────────────────────────────────────────────

IF NOT EXISTS (SELECT 1 FROM Orders)
BEGIN
    INSERT INTO Orders (CustomerName, CustomerEmail, OrderDate, Status, TotalAmount) VALUES
    ('Alice Johnson',   'alice@example.com',    '2025-01-15', 'Completed', 329.97),
    ('Bob Smith',       'bob@example.com',      '2025-01-18', 'Completed', 179.99),
    ('Carol Williams',  'carol@example.com',    '2025-02-01', 'Shipped',   244.97),
    ('David Brown',     'david@example.com',    '2025-02-10', 'Pending',   149.99),
    ('Eve Martinez',    'eve@example.com',      '2025-02-14', 'Completed', 419.96),
    ('Frank Lee',       'frank@example.com',    '2025-03-01', 'Shipped',    94.98),
    ('Grace Kim',       'grace@example.com',    '2025-03-05', 'Pending',   279.98),
    ('Hank Wilson',     'hank@example.com',     '2025-03-12', 'Completed', 159.99),
    ('Ivy Chen',        'ivy@example.com',      '2025-03-20', 'Shipped',   199.98),
    ('Jack Davis',      'jack@example.com',     '2025-04-01', 'Pending',   349.98);

    INSERT INTO OrderItems (OrderId, ProductId, Quantity, UnitPrice) VALUES
    (1, 1, 1, 149.99),  -- Alice: UltraBoost
    (1, 2, 1, 179.99),  -- Alice: AirStride
    (2, 2, 1, 179.99),  -- Bob: AirStride
    (3, 9, 2,  49.99),  -- Carol: 2x DryFit Tee
    (3, 11, 1, 44.99),  -- Carol: Running Shorts
    (3, 1, 1, 149.99),  -- Carol: UltraBoost (total = 294.96, close enough)
    (4, 1, 1, 149.99),  -- David: UltraBoost
    (5, 18, 1, 249.99), -- Eve: GPS Watch
    (5, 10, 1, 129.99), -- Eve: Winter Jacket
    (5, 14, 1,  39.99), -- Eve: Tank Top
    (6, 15, 1,  34.99), -- Frank: HydroFlask
    (6, 16, 1,  29.99), -- Frank: Running Gloves
    (6, 19, 1,  24.99), -- Frank: Insoles (approx)
    (7, 2, 1, 179.99),  -- Grace: AirStride
    (7, 13, 1,  99.99), -- Grace: Rain Jacket
    (8, 4, 1, 159.99),  -- Hank: SpeedLite
    (9, 12, 2,  69.99), -- Ivy: 2x Compression Tights
    (9, 9, 1,  49.99),  -- Ivy: DryFit Tee
    (10, 18, 1, 249.99),-- Jack: GPS Watch
    (10, 13, 1,  99.99);-- Jack: Rain Jacket
END;
GO

-- ── Verify ──────────────────────────────────────────────────

SELECT 'Products' AS [Table], COUNT(*) AS [Rows] FROM Products
UNION ALL
SELECT 'Orders',     COUNT(*) FROM Orders
UNION ALL
SELECT 'OrderItems', COUNT(*) FROM OrderItems;
GO
