CREATE TABLE IF NOT EXISTS transactions (
    transaction_id INTEGER PRIMARY KEY,
    description VARCHAR(30)
);

INSERT INTO transactions (transaction_id, description) VALUES
(10234567, 'Online purchase at Amazon'),
(20456789, 'Gas station payment'),
(30678901, 'Grocery store checkout'),
(40891234, 'Restaurant dinner bill'),
(50123456, 'Monthly subscription fee'),
(60345678, 'ATM cash withdrawal'),
(70567890, 'Electric utility payment'),
(80789012, 'Coffee shop purchase'),
(90901234, 'Movie ticket booking'),
(11223344, 'Pharmacy medication buy'),
(22334455, 'Hotel accommodation charge'),
(33445566, 'Airline ticket purchase'),
(44556677, 'Car rental service'),
(55667788, 'Mobile phone bill payment'),
(66778899, 'Internet service charge'),
(77889900, 'Gym membership renewal'),
(88990011, 'Book store purchase'),
(99001122, 'Pet supplies shopping'),
(12345678, 'Home insurance premium'),
(23456789, 'Streaming service fee');
